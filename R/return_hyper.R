
#' Return model hyperparameters across validation datasets
#'
#' The purpose of this function and its plot() method is to investigate
#' the stability of hyperparameters in the nested cross-validation and across
#' forecast horizons.
#'
#' @param forecast_model An object of class 'forecast_model' from train_model().
#' @param hyper_function A user-defined function for retrieving model hyperparameters (requierd).
#' @return An object of class 'forecast_model_hyper': A data.frame of model-specific hyperparameters.
#' @example /R/examples/example_return_hyper.R
#' @export
return_hyper <- function(forecast_model, hyper_function = NULL) {

  model_results <- forecast_model

  if(!methods::is(model_results, "forecast_model")) {
    stop("The 'model_results' argument takes a list of objects of class 'forecast_model' as input. Run train_model() first.")
  }

  outcome_cols <- attributes(model_results)$outcome_cols
  outcome_names <- attributes(model_results)$outcome_names
  horizon <- attributes(model_results)$horizons

  # Defined here to catch (from '<<-' below) the user-defined hyperparameter names in hyper_function.
  hyper_names <- NULL

  # Seq along horizon > window_number
  data_out <- lapply(seq_along(model_results), function(i) {

    data_plot <- lapply(seq_along(model_results[[i]]), function(j) {

      data_results <- model_results[[i]][[j]]

      data_hyper <- hyper_function(data_results$model)
      hyper_names <<- names(data_hyper)

      data_plot <- data.frame("model" = attributes(model_results)$model_name,
                              "horizon" = horizon[i],
                              "window_length" = data_results$window,
                              "window_number" = j,
                              "valid_window_start" = min(data_results$valid_indices),
                              "valid_window_stop" = max(data_results$valid_indices),
                              "valid_window_midpoint" = mean(data_results$valid_indices))

      data_plot <- cbind(data_plot, data_hyper)

      return(data_plot)
    })
    data_plot <- dplyr::bind_rows(data_plot)

    return(data_plot)
  })
  data_out <- dplyr::bind_rows(data_out)

  attr(data_out, "outcome_cols") <- outcome_cols
  attr(data_out, "outcome_names") <- outcome_names
  attr(data_out, "hyper_names") <- hyper_names

  class(data_out) <- c("forecast_model_hyper", class(data_out))

  return(data_out)
}
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------

#' Plot hyperparameters
#'
#' Plot hyperparameter stability and relationship with error metrics across validation datasets.
#'
#' @param data_hyper An object of class 'forecast_model_hyper' from return_hyper().
#' @param data_results An object of class 'training_results' from predict.forecast_model(..., data_forecast = NULL).
#' @param data_error An object of class 'validation_error' from return_error(..., data_test = NULL).
#' @param type Select plot type; 'stability' is the default plot.
#' @param horizons Filter results by horizon (optional).
#' @param windows Filter results by validation window number (optional).
#' @return Hyperparameter plots of class 'ggplot'.
#' @example /R/examples/example_return_hyper.R
#' @export
plot.forecast_model_hyper <- function(data_hyper, data_results, data_error,
                                      type = c("stability", "error"),
                                      horizons = NULL,
                                      windows = NULL) {

  if(!methods::is(data_hyper, "forecast_model_hyper")) {
    stop("The 'data_hyper' argument takes an object of class 'forecast_model_hyper' as input. Run return_hyper() first.")
  }

  if(!methods::is(data_results, "training_results")) {
    stop("The 'data_results' argument takes an object of class 'training_results' as input. Run predict.forecast_model(..., data_forecast = NULL) first.")
  }

  if(!methods::is(data_error, "validation_error")) {
    stop("The 'data_error' argument takes an object of class 'validation_error' as input. Run return_error(..., data_test = NULL) first.")
  }

  type <- type[1]

  data_results <- dplyr::distinct(data_results, valid_indices, .keep_all = TRUE)

  outcome_cols <- attributes(data_hyper)$outcome_cols
  outcome_names <- attributes(data_hyper)$outcome_names
  hyper_names <- attributes(data_hyper)$hyper_names

  hyper_num <- unlist(lapply(data_hyper[, hyper_names], function(x) {inherits(x, c("numeric", "double", "integer"))}))
  hyper_num <- hyper_names[hyper_num]

  hyper_cat <- unlist(lapply(data_hyper[, hyper_names], function(x) {inherits(x, c("factor", "character"))}))
  hyper_cat <- hyper_names[hyper_cat]

  data_plot <- data_hyper

  horizons <- if (is.null(horizons)) {unique(data_plot$horizon)} else {horizons}
  windows <- if (is.null(windows)) {unique(data_plot$window_number)} else {windows}

  data_plot <- data_plot[data_plot$horizon %in% horizons &
                         data_plot$window_number %in% windows, ]

  data_plot$group <- paste0("00", data_plot$horizon)
  data_plot$group <- substr(data_plot$group, nchar(data_plot$group) - 2, nchar(data_plot$group))
  data_plot$group <- paste0(data_plot$group, "-", data_plot$window_length)
  data_plot$group <- ordered(data_plot$group)

  if (length(hyper_num) > 0) {
    data_hyper_num <- tidyr::gather(data_plot, "hyper", "value",
                                    -!!names(data_plot)[!names(data_plot) %in% hyper_num])
  }

  if (length(hyper_cat) > 0) {
    data_hyper_cat <- tidyr::gather(data_plot, "hyper", "value",
                                    -!!names(data_plot)[!names(data_plot) %in% hyper_cat])
  }

  if (type == "stability") {
    p <- ggplot()
    if (length(hyper_num) > 0) {
      if (length(unique(data_hyper_num$window_number)) > 1) {
        p <- p + geom_line(data = data_hyper_num, aes(x = ordered(window_number), y = value, group = group), alpha = .5)
      }
      p <- p + geom_point(data = data_hyper_num, aes(x = ordered(window_number), y = value, group = group))
    }
    if (length(hyper_cat) > 0) {
      p <- p + geom_bar(data = data_hyper_cat, aes(x = ordered(window_number), fill = ordered(value)), position = position_dodge(), alpha = .5)
    }
    p <- p + facet_grid(hyper ~ horizon, scales = "free")
    p <- p + theme_bw()
    p <- p + xlab("Window number") + ylab("Hyperparameter value/count") +
      labs(color = "Horizon - Window", fill = "Hyper") + ggtitle("Hyperparameter Stability Across Validation Windows")
    return(p)
  }

  if (type == "error") {

    error_metrics <- attributes(data_error)$error_metrics

    data_error_merge <- data_error$error_by_window

    data_error_merge <- dplyr::select(data_error_merge,
                                      model, horizon, window_number,
                                      error_metrics)
    data_error_merge$model <- as.character(data_error_merge$model)

    if (length(hyper_num) > 0) {
      data_hyper_num$model <- as.character(data_hyper_num$model)
      data_hyper_num <- dplyr::inner_join(data_error_merge, data_hyper_num, by = c("model", "horizon", "window_number"))
      data_hyper_num <- tidyr::gather(data_hyper_num, "error_metric", "error",
                    -!!names(data_hyper_num)[!names(data_hyper_num) %in% error_metrics])
      }

    if (length(hyper_cat) > 0) {
      data_hyper_cat$model <- as.character(data_hyper_cat$model)
      data_hyper_cat <- dplyr::inner_join(data_hyper_cat, data_error_merge, by = c("model", "horizon", "window_number"))
      data_hyper_cat <- tidyr::gather(data_hyper_cat, "error_metric", "error",
                                      -!!names(data_hyper_cat)[!names(data_hyper_cat) %in% error_metrics])
    }

    p <- ggplot()
    if (length(hyper_num) > 0) {
      if (length(unique(data_hyper_num$window_number)) > 1) {
        p <- p + geom_line(data = data_hyper_num, aes(x = value, y = error, color = factor(horizon)), alpha = .5, show.legend = FALSE)
      }
      p <- p + geom_point(data = data_hyper_num, aes(x = value, y = error, color = factor(horizon)), alpha = .5)
    }
    if (length(hyper_cat) > 0) {
      p <- p + geom_bar(data = data_hyper_cat, aes(x = ordered(value), fill = ordered(horizon)), position = position_dodge(), alpha = .5)
    }
    p <- p + scale_color_viridis_d()
    p <- p + facet_grid(error_metric ~ hyper, scales = "free")
    p <- p + theme_bw()
    p <- p + xlab("Hyperparameter value") + ylab("Error metric") +
      labs(color = "Horizon") + ggtitle("Forecast Error and Hyperparameter Values - Faceted by horizon")
    return(p)
  }
}
