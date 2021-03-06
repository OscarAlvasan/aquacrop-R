#### Aquacrop make_projects
# https://github.com/jrodriguez88/aquacrop-R
# Author: Rodriguez-Espinoza J.
# 2019


### Load packages, path and functions
library(tictoc)

tic()
library(tidyverse)
library(data.table)
library(lubridate)


# Path of aquacrop files
aquacrop_files <- paste0(getwd(), "/data/aquacrop_files/")
plugin_path <- paste0(getwd(), "/plugin/")




# function to calculate HUH (growing thermal units) _ tbase,    topt,and thigh depends of crop
HUH_cal <- function(tmax, tmin, tbase = 8, topt = 30, thigh = 42.5) {
    
    tav <- (tmin + tmax)/2
    
    h <- 1:24
    
    Td <- tav + (tmax - tmin)*cos(0.2618*(h - 14))/2 
    
    huh <- Td %>% enframe(name = NULL, "td") %>%
        mutate(HUH = case_when(td <= tbase | td >= thigh ~ 0,
                               td > tbase | td <= topt ~ (td - tbase)/24,
                               td > topt | td < thigh ~ (topt-(td - topt)*(topt - tbase)/(thigh - topt))/24))
    
    sum(huh$HUH)   
    
} 


## set locality and planting_window dates (<= 1 month). require wth_data 
clim_data <- read.csv("data/weather_to_aquacrop.csv") %>% 
    mutate(date = ymd(date)) %>% 
    mutate(HUH = map2_dbl(tmax, tmin, HUH_cal))


## Set sowing dates. planting_window dates (<= 40  days), 
## compute by "weeks". Or seven "days"
max_crop_duration <- 140
star_sow <- c(6,24)   #c(month, day)
end_sow <- c(6,24)   #c(month, day)


## Function to create sowing dates vector, 
sow_date_cal <- function(start_sow, end_sow, clim_data, by = "weeks") {
    
    start_sowing_date <- make_date(month = star_sow[1], day = star_sow[2]) %>% yday
    end_sowing_date <- make_date(month = end_sow[1], day = end_sow[2]) %>% yday
    
    seq.Date(range(clim_data$date)[1], 
             range(clim_data$date)[2], by=by) %>%
        enframe(name = NULL, value = "sow_dates") %>%
        filter(yday(sow_dates) >= start_sowing_date, 
               yday(sow_dates) <= end_sowing_date) %>% pull(sow_dates)
}
sowing_dates <- sow_date_cal(star_sow, end_sow, clim_data, by = "days")


## Function to create all combinations of files and parameters(params)
##  and default parameters(def_params)
make_param_df <- function(path, max_crop_duration, sowing_dates){
    ### load aquacrop files
    clim_file <- list.files(path, pattern = "CLI") %>% str_remove(".CLI")
    co2_file <- list.files(path, ".CO2")
    crop_file <- list.files(path, ".CRO")
    irri_file <- list.files(path, ".IRR") %>% c(., "rainfed")
    man_file <- list.files(path, ".MAN")
    soil_file <- list.files(path, ".SOL")
    ini_file <- list.files(path, ".SW0")
    proj_file <- list.files(path, ".PRM")
    
    ### Default parameters,  
    def_params <<- read_lines(paste0(aquacrop_files, proj_file), skip = 6, n_max = 21) 
    
    
    ### Create multiple combinations of params
        params <<- expand.grid(aquacrop_files,
                          clim_file,
                          co2_file,
                          crop_file,
                          irri_file, 
                          man_file,
                          soil_file,
                          ini_file,
                          max_crop_duration,
                          sowing_dates) %>% 
        as_tibble() %>%
        setNames(c("aquacrop_files",
                   "clim_file",
                   "co2_file",
                   "crop_file",
                   "irri_file", 
                   "man_file",
                   "soil_file",
                   "ini_file",
                   "max_crop_duration",
                   "sowing_date"))

    
}
make_param_df(aquacrop_files, max_crop_duration, sowing_dates)


## Function to calculate and create crop growing cycles
cal_cycles_project <- function(clim_data,
                               aquacrop_files,
                               clim_file,
                               co2_file,
                               crop_file,
                               irri_file, 
                               man_file,
                               soil_file,
                               ini_file,
                               max_crop_duration,
                               sowing_date) {
    
    # path files
    path_files <- aquacrop_files %>% str_replace_all(pattern = "/", replacement = "\\\\")
    
    ### extract "GDDays: from sowing to maturity" from CRO_file
    gdd_mt <- read_lines(file = paste0(aquacrop_files, crop_file)) %>%
        str_subset("GDDays: from sowing to maturity|GDDays: from transplanting to maturity") %>% 
        str_extract("[0-9]+") %>% as.numeric
    
    
    # calculate crop duration 
    crop_duration <- clim_data %>% 
        dplyr::filter(date >= sowing_date,
                      date <= sowing_date + max_crop_duration) %>%
        mutate(sum_gdd = cumsum(HUH)) %>%
        dplyr::filter(sum_gdd<= gdd_mt) %>% 
        count() %>% pull(n)+3
    
    # Calculate numeric dates
    first_day <- as.numeric(sowing_date - make_date(1900, 12, 31))
    last_day <- first_day + crop_duration
    mat_date <- as.Date(last_day, origin = make_date(1900, 12, 31))
    
    #Write grow cycles
    path_data <- function(){
        
        cat(paste0(first_day, "    : First day of simulation period - ", format(sowing_date, "%d %b %Y")))
        cat('\n')
        cat(paste0(last_day,  "    : Last day of simulation period - ",  format(mat_date, "%d %b %Y")))
        cat('\n')
        cat(paste0(first_day, "    : First day of cropping period - " , format(sowing_date, "%d %b %Y")))
        cat('\n')
        cat(paste0(last_day,  "    : Last day of cropping period - "  , format(mat_date, "%d %b %Y")))
        cat('\n')    
        cat("-- 1. Climate (CLI) file", sep = '\n')
        cat(paste0(clim_file, ".CLI"), sep = '\n')
        cat(paste0(path_files), sep = '\n')
        cat("1.1 Temperature (TMP) file", sep = '\n')
        cat(paste0(clim_file, ".Tnx"), sep = '\n') 
        cat(paste0(path_files), sep = '\n')
        cat("1.2 Reference ET (ETo) file", sep = '\n')
        cat(paste0(clim_file, ".ETo"), sep = '\n')
        cat(paste0(path_files), sep = '\n')
        cat("1.3 Rain (PLU) file", sep = '\n')
        cat(paste0(clim_file, ".PLU"), sep = '\n')
        cat(paste0(path_files), sep = '\n')
        cat("1.4 Atmospheric CO2 (CO2) file", sep = '\n')
        cat(paste(co2_file), sep = '\n')
        cat(paste0(path_files), sep = '\n')
        cat("-- 2. Crop (CRO) file", sep = '\n')
        cat(paste(crop_file), sep = '\n')
        cat(paste0(path_files), sep = '\n')
        cat("-- 3. Irrigation (IRR) file", sep = '\n')
        if(irri_file=="rainfed"){
            cat("(None)", sep = '\n')
            cat("(None)", sep = '\n')
        } else {
            cat(paste(irri_file), sep = '\n')
            cat(paste0(path_files), sep = '\n')
        }
        cat("-- 4. Management (MAN) file", sep = '\n')
        cat(paste(man_file), sep = '\n')
        cat(paste0(path_files), sep = '\n')
        cat("-- 5. Soil profile (SOL) file", sep = '\n')
        cat(paste(soil_file), sep = '\n')
        cat(paste0(path_files), sep = '\n')
        cat("-- 6. Groundwater (GWT) file", sep = '\n')
        cat("(None)", sep = '\n')
        cat("(None)", sep = '\n')
        cat("-- 7. Initial conditions (SW0) file", sep = '\n')
        cat(paste(ini_file), sep = '\n')
        cat(paste0(path_files), sep = '\n')
        cat("-- 8. Off-season conditions (OFF) file", sep = '\n')
        cat("(None)", sep = '\n')
        cat("(None)", sep = '\n')
    }
    
    list(capture.output(path_data()))
    
}


## Function to compute all runs for params table
runs_cal <- function(params, clim_data) {
    
    params %>% mutate(runs = cal_cycles_project(clim_data, 
                                                aquacrop_files,
                                                clim_file,
                                                co2_file,
                                                crop_file,
                                                irri_file, 
                                                man_file,
                                                soil_file,
                                                ini_file,
                                                max_crop_duration,
                                                sowing_date)) 
    
}

sim_cycles <- split(params, 1:nrow(params)) %>% 
    map(., ~runs_cal(., clim_data)) %>%
    bind_rows() 


## Write PRM files
write_projects <- function(sim_cycles, path, def_params){
    
    #    description <-  paste(unique(sim_cycles$crop_file), 
    #                       unique(sim_cycles$clim_file),
    #                       unique(sim_cycles$soil_file),
    #                       unique(sim_cycles$irri_file), sep = " - ")
    
    prm_name <- paste0(unique(sim_cycles$clim_file), "_",
                       unique(sim_cycles$crop_file), "_",
                       unique(sim_cycles$soil_file), "_",
                       unique(sim_cycles$irri_file)) %>% 
        str_replace_all(pattern = "[.]+", replacement = "") %>%
        paste0(., ".PRM")
    
    suppressWarnings(dir.create(paste0(path, "/", "LIST")))
    
    sink(file = paste(path, "LIST", prm_name, sep = "/"), append = F)
    cat(paste("I am groot"))
    cat('\n')
    cat("6.0       : AquaCrop Version (March 2017)")
    cat('\n')
    writeLines(sim_cycles$runs[[1]][1:4])
    writeLines(def_params)
    writeLines(sim_cycles$runs[[1]][-c(1:4)])
    walk(.x=sim_cycles$runs[-1], ~writeLines(.x))
    sink()    
    
}

map(.x = split(sim_cycles, 
               list(sim_cycles$crop_file, 
                    sim_cycles$irri_file, 
                    sim_cycles$soil_file)),
    ~write_projects(.x, plugin_path, def_params))

#    toc()
#25.57 sec elapsed by 1 crop, 





#tic()
system("plugin/ACsaV60.exe")
#toc()
# 1400.54 sec elapsed 
# set: 1 climate, 
#      2 crops, 6 soils, 2 irri, 21 years , 6 planting dates/year (by week)
# 3024 simulations




