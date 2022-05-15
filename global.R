# Load needed packages.
library(shiny)
library(shinyhelper)
library(shinyjs)
library(shinydashboard)
library(shinyWidgets)
library(data.table)
library(DT)
library(readr)
library(lubridate)
library(RSQLite)
library(DBI)
library(rvest)
library(xml2)
library(httr)
library(desc)
library(dplyr)
library(tools)
library(stringr)
library(tidyverse)
library(loggit)
library(shinycssloaders)
library(rAmCharts)
library(devtools)
library(plotly)
library(riskmetric) # devtools::install_github("pharmaR/riskmetric")
library(formattable)
library(rintrojs)
library(bslib)
library(shinymanager)
library(glue)

passphrase <- 'somepassphrase'

#' Displays a helper message. By default, it informs the user that he should
#' select a package.
showHelperMessage <- function(message = "Please select a package"){
  h6(message,
     style = 
       "text-align: center;
        color: gray;
        padding-top: 50px;")
}

# Displays formatted comments.
showComments <- function(pkg_name, comments){
  if (length(pkg_name) == 0)
    return("")
  
  ifelse(
    length(comments$user_name) == 0, 
    "No comments",
    paste0(
      "<div class='well'>",
      icon("user-tie"), " ", "user: ", comments$user_name, ", ", 
      icon("user-shield"), " ", "role: ", comments$user_role, ", ",
      icon("calendar-alt"), " ", "date: ", comments$added_on,
      br(), br(), 
      comments$comment,
      "</div>",
      collapse = ""
    )
  )
}
