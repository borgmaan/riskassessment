#' 'Upload Package' UI
#' 
#' @param id a module id
#' 
#' 
#' @importFrom DT dataTableOutput
#' 
uploadPackageUI <- function(id) {
  fluidPage(
    br(), br(),
    
    introJSUI(NS(id, "introJS")),
    
    tags$head(tags$style(".shiny-notification {font-size:30px; color:darkblue; position: fixed; width:415px; height: 150px; top: 75% ;right: 10%;")),
    
    fluidRow(
      
      column(
        width = 4,
        div(
          id = "type-package-group",
          style = "display: flex;",
          selectizeInput(NS(id, "pkg_lst"), "Type Package Name(s)", choices = NULL, multiple = TRUE, 
                         options = list(create = TRUE, showAddOptionOnCreate = FALSE, 
                                        onFocus = I(paste0('function() {Shiny.setInputValue("', NS(id, "load_cran"), '", "load", {priority: "event"})}')))),
          actionButton(NS(id, "add_pkgs"), shiny::icon("angle-right"),
                       style = 'height: calc(1.5em + 1.5rem + 2px)'),
          tags$head(tags$script(I(paste0('$(window).on("load resize", function() {$("#', NS(id, "add_pkgs"), '").css("margin-top", $("#', NS(id, "pkg_lst"), '-label")[0].scrollHeight + .5*parseFloat(getComputedStyle(document.documentElement).fontSize));});'))))
        )
      ),
      column(width = 1),
      column(
        width = 4,
        div(id = "upload-file-grp",
            fileInput(
              inputId = NS(id, "uploaded_file"),
              label = "Or Upload a CSV file",
              accept = ".csv",
              placeholder = "No file selected"
            )
        ),
        actionLink(NS(id, "upload_format"), "View Sample Dataset")
      )
    ),
    
    # Display the summary information of the uploaded csv.
    fluidRow(column(width = 12, htmlOutput(NS(id, "upload_summary_text")))),
    
    # Summary of packages uploaded.
    fluidRow(column(width = 12, DT::dataTableOutput(NS(id, "upload_pkgs_table"))))
  )
}


#' Server logic for the 'Upload Package' module
#'
#' @param id a module id
#' 
#' @importFrom riskmetric pkg_ref
#' @importFrom rintrojs introjs
#' @importFrom utils read.csv available.packages
#' @importFrom rvest read_html html_nodes html_text
#' 
uploadPackageServer <- function(id) {
  moduleServer(id, function(input, output, session) {
    
    # Determine which guide to use for IntroJS.
    upload_pkg_txt <- reactive({
      req(uploaded_pkgs())
      
      if(nrow(uploaded_pkgs()) > 0) 
        upload_pkg_complete 
      else 
        upload_pkg
    })
    
    cran_pkgs <- reactiveVal()

    observeEvent(input$load_cran, {
      if (!isTruthy(cran_pkgs())) {
        cran_pkgs(available.packages("https://cran.rstudio.com/src/contrib")[,1])
      }
    },
    once = TRUE)
    
    observeEvent(cran_pkgs(), {
      req(cran_pkgs())
      updateSelectizeInput(session, "pkg_lst", choices = cran_pkgs(), server = TRUE)
    })
    
    
    # Start introjs when help button is pressed. Had to do this outside of
    # a module in order to take a reactive data frame of steps
    observeEvent(
      input[["introJS-help"]], # notice input contains "id-help"
      rintrojs::introjs(session,
                        options = list(
                          steps = 
                            upload_pkg_txt() %>%
                            union(sidebar_steps),
                          "nextLabel" = "Next",
                          "prevLabel" = "Previous"
                        )
      )
    )
    
    uploaded_pkgs00 <- reactiveVal()
    
    observeEvent(input$uploaded_file, {
      req(input$uploaded_file)
      
      if(is.null(input$uploaded_file$datapath))
        uploaded_pkgs00(validate('Please upload a nonempty CSV file.'))
      
      uploaded_packages <- read.csv(input$uploaded_file$datapath, stringsAsFactors = FALSE)
      np <- nrow(uploaded_packages)
      if(np == 0)
        uploaded_pkgs00(validate('Please upload a nonempty CSV file.'))
      
      if(!all(colnames(uploaded_packages) == colnames(template)))
        uploaded_pkgs00(validate("Please upload a CSV with a valid format."))
      
      # Add status column and remove white space around package names.
      uploaded_packages <- uploaded_packages %>%
        dplyr::mutate(
          status = rep('', np),
          package = trimws(package),
          version = trimws(version)
        )
      
      uploaded_pkgs00(uploaded_packages)
    })
    
    
    
    observeEvent(input$add_pkgs, {
      req(input$pkg_lst)
      
      np <- length(input$pkg_lst)
      uploaded_packages <-
        dplyr::tibble(
          package = input$pkg_lst,
          version = rep('0.0.0', np),
          status = rep('', np)
        )
      
      updateSelectizeInput(session, "pkg_lst", selected = "")
      
      uploaded_pkgs00(uploaded_packages)
    })
    
    uploaded_pkgs <- reactiveVal(data.frame())
    # Save all the uploaded packages, marking them as 'new', 'not found', or
    # 'duplicate'.
    observeEvent(uploaded_pkgs00(), {

      uploaded_packages <- uploaded_pkgs00()
      np <- nrow(uploaded_packages)
      
      if (!isTruthy(cran_pkgs())) {
        cran_pkgs(available.packages("https://cran.rstudio.com/src/contrib")[,1])
      }
      
      # Start progress bar. Need to establish a maximum increment
      # value based on the number of packages, np, and the number of
      # incProgress() function calls in the loop, plus one to show
      # the incProgress() that the process is completed.
      withProgress(
        max = (np * 5) + 1, value = 0,
        message = "Uploading Packages to DB:", {
          
          for (i in 1:np) {
            
            user_ver <- uploaded_packages$version[i]
            incProgress(1, detail = glue::glue("{uploaded_packages$package[i]} {user_ver}"))
            
            if (grepl("^[[:alpha:]][[:alnum:].]*[[:alnum:]]$", uploaded_packages$package[i])) {
              # run pkg_ref() to get pkg version and source info
              ref <- riskmetric::pkg_ref(uploaded_packages$package[i])
            } else {
              ref <- list(name = uploaded_packages$package[i],
                          source = "name_bad")
            }
            
            if (ref$source %in% c("pkg_missing", "name_bad")) {
              incProgress(1, detail = 'Package {uploaded_packages$package[i]} not found')
              
              # Suggest alternative spellings using utils::adist() function
              v <- utils::adist(uploaded_packages$package[i], cran_pkgs(), ignore.case = FALSE)
              rlang::inform(paste("Package name",uploaded_packages$package[i],"was not found."))
              
              suggested_nms <- paste("Suggested package name(s):",paste(head(cran_pkgs()[which(v == min(v))], 10),collapse = ", "))
              rlang::inform(suggested_nms)
              
              uploaded_packages$status[i] <- HTML(paste0('<a href="#" title="', suggested_nms, '">not found</a>'))
              
              if (ref$source == "pkg_missing")
                loggit::loggit('WARN',
                               glue::glue('Package {ref$name} was flagged by riskmetric as {ref$source}.'))
              else
                loggit::loggit('WARN',
                               glue::glue("Riskmetric can't interpret '{ref$name}' as a package reference."))
              
              next
            }
            
            ref_ver <- as.character(ref$version)
            
            if(user_ver == ref_ver) ver_msg <- ref_ver
            else ver_msg <- glue::glue("{ref_ver}, not '{user_ver}'")
            
            as.character(ref$version)
            deets <- glue::glue("{uploaded_packages$package[i]} {ver_msg}")
            
            # Save version.
            incProgress(1, detail = deets)
            uploaded_packages$version[i] <- as.character(ref$version)
            
            found <- nrow(dbSelect(glue::glue(
              "SELECT name
              FROM package
              WHERE name = '{uploaded_packages$package[i]}'")))
            
            uploaded_packages$status[i] <- ifelse(found == 0, 'new', 'duplicate')
            
            # Add package and metrics to the db if package is not in the db.
            if(!found) {
              # Get and upload pkg general info to db.
              incProgress(1, detail = deets)
              insert_pkg_info_to_db(uploaded_packages$package[i])
              # Get and upload maintenance metrics to db.
              incProgress(1, detail = deets)
              insert_maintenance_metrics_to_db(uploaded_packages$package[i])
              # Get and upload community metrics to db.
              incProgress(1, detail = deets)
              insert_community_metrics_to_db(uploaded_packages$package[i])
            }
          }
          
          incProgress(1, detail = "   **Completed Pkg Uploads**")
          Sys.sleep(0.25)
          
        }) #withProgress
      
      uploaded_pkgs(uploaded_packages)
    })
    
    # Download the sample dataset.
    output$download_sample <- downloadHandler(
      filename = function() {
        paste("template", ".csv", sep = "")
      },
      content = function(file) {
        write.csv(template, file, row.names = F)
      }
    )
    
    # Uploaded packages summary.
    output$upload_summary_text <- renderText({
      req(uploaded_pkgs)
      req(nrow(uploaded_pkgs()) > 0)
      
      loggit::loggit("INFO",
                     paste("Uploaded file:", input$uploaded_file$name, 
                           "Total Packages:", nrow(uploaded_pkgs()),
                           "New Packages:", sum(uploaded_pkgs()$status == 'new'),
                           "Undiscovered Packages:", sum(grepl('not found', uploaded_pkgs()$status)),
                           "Duplicate Packages:", sum(uploaded_pkgs()$status == 'duplicate')),
                     echo = FALSE)
      
      as.character(tagList(
        br(), br(),
        hr(),
        div(id = "upload_summary_div",
            h5("Summary of uploaded package(s)"),
            br(),
            p(tags$b("Total Packages: "), nrow(uploaded_pkgs())),
            p(tags$b("New Packages: "), sum(uploaded_pkgs()$status == 'new')),
            p(tags$b("Undiscovered Packages: "), sum(grepl('not found', uploaded_pkgs()$status))),
            p(tags$b("Duplicate Packages: "), sum(uploaded_pkgs()$status == 'duplicate')),
            p("Note: The assessment will be performed on the latest version of each
          package, irrespective of the uploaded version.")
        )
      ))
    })
    
    # Uploaded packages table.
    output$upload_pkgs_table <- DT::renderDataTable({
      req(nrow(uploaded_pkgs()) > 0)
      
      DT::datatable(
        uploaded_pkgs(),
        escape = FALSE,
        class = "cell-border",
        selection = 'none',
        extensions = 'Buttons',
        options = list(
          searching = FALSE,
          sScrollX = "100%",
          lengthChange = FALSE,
          aLengthMenu = list(c(5, 10, 20, 100, -1), list('5', '10', '20', '100', 'All')),
          iDisplayLength = 5
        )
      )
    })
    
    # View sample dataset.
    observeEvent(input$upload_format, {
      DT::dataTableOutput(NS(id, "sampletable"))
      
      showModal(modalDialog(
        size = "l",
        easyClose = TRUE,
        footer = "",
        h5("Sample Dataset", style = 'text-align: center !important'),
        hr(),
        br(),
        fluidRow(
          column(
            width = 12,
            output$sampletable <- DT::renderDataTable(
              DT::datatable(
                template,
                escape = FALSE,
                editable = FALSE,
                filter = 'none',
                selection = 'none',
                extensions = 'Buttons',
                options = list(
                  sScrollX = "100%",
                  aLengthMenu = list(c(5, 10, 20, 100, -1), list('5', '10', '20', '100', 'All')),
                  iDisplayLength = 5,
                  dom = 't'
                )
              )))
        ),
        br(),
        fluidRow(column(align = 'center', width = 12,
                        downloadButton(NS(id, "download_sample"), "Download")))
      ))
    })
    
    list(
      names = uploaded_pkgs
    )
  })
}
