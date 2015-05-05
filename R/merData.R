#' @title Clean up variable names in data frames
#' @name sanitizeNames
#' @description Strips out transformations from variable names in data frames
#' @param data a data.frame
#' @return a data frame with variable names cleaned to remove factor() construction
sanitizeNames <- function(data){
  badFac <- grep("factor\\(", names(data))
  for(i in badFac){
    names(data)[i] <- gsub("factor\\(", "", names(data)[i])
    names(data)[i] <- gsub("\\)", "", names(data)[i])
  }
  row.names(data) <- NULL
  return(data)
}

#' @title Remove attributes from a data.frame
#' @name stripAttributes
#' @description Strips attributes off of a data frame that come with a merMod model.frame
#' @param data a data.frame
#' @return a data frame with variable names cleaned to remove all attributes except for
#' names, row.names, and class
stripAttributes <- function(data){
  attr <- names(attributes(data))
  good <- c("names", "row.names", "class")
  for(i in attr[!attr %in% good]){
    attr(data, i) <- NULL
  }
  return(data)
}

#' @title Select a random observation from model data
#' @name randomObs
#' @description Select a random observation from the model frame of a merMod
#' @param merMod an object of class merMod
#' @return a data frame with a single row for a random observation, but with full
#' factor levels. See details for more.
#' @details Each factor variable in the data frame has all factor levels from the
#' full model.frame stored so that the new data is compatible with predict.merMod
#' @export
randomObs <- function(merMod){
  out <- merMod@frame[sample(1:nrow(merMod@frame), 1),]
  chars <- !sapply(out, is.numeric)
  for(i in names(out[, chars])){
    out[, i] <- superFactor(out[, i], fullLev = unique(merMod@frame[, i]))
  }
  out <- stripAttributes(out)
  return(out)
}

#' @title Collapse a dataframe to a single average row
#' @name collapseFrame
#' @description Take an entire dataframe and summarize it in one row by using the
#' mean and mode.
#' @param data a data.frame
#' @return a data frame with a single row
#' @details Each character and factor variable in the data.frame is assigned to the
#' modal category and each numeric variable is collapsed to the mean. Currently if
#' mode is a tie, returns a "."
collapseFrame <- function(data){
  chars <- !sapply(data, is.numeric)
  chars <- names(data[, chars])
  nums <- sapply(data, is.numeric)
  nums <- names(data[, nums])

  numDat <- apply(data[, nums], 2, mean)
  statmode <- function(x){
    z <- table(as.vector(x))
    m <- names(z)[z == max(z)]
    if (length(m) == 1) {
      return(m)
    }
    return(".")
  }
  charDat <- apply(data[, chars], 2, statmode)
  cfdata <- cbind(as.data.frame(t(numDat)), as.data.frame(t(charDat)))
  cfdata <- cfdata[, names(data)]
  return(cfdata)
}


#' @title Subset a data.frame using a list of conditions
#' @name subsetList
#' @description Split a data.frame by elements in a list
#' @param data a data.frame
#' @param list a named list of splitting conditions
#' @return a data frame with values that match the conditions in the list
subsetList <- function(data, list){
  for(i in names(list)){
    data <- split(data, data[, i])
    data <- data[[list[[i]]]]
    data <- as.data.frame(data)
  }
  return(data)
}

#' @title Find the average observation for a merMod object
#' @name averageObs
#' @description Extract a data frame of a single row that represents the
#' average observation in a merMod object. This function also allows the
#' user to pass a series of conditioning argument to calculate the average
#' observation conditional on other characteristics.
#' @param merMod a merMod object
#' @param varList optional, a named list of conditions to subset the data on
#' @return a data frame with a single row for the average observation, but with full
#' factor levels. See details for more.
#' @details Each character and factor variable in the data.frame is assigned to the
#' modal category and each numeric variable is collapsed to the mean. Currently if
#' mode is a tie, returns a "." Uses the collapseFrame function.
averageObs <- function(merMod, varList = NULL){
  if(!missing(varList)){
    data <- subsetList(merMod@frame, varList)
    if(nrow(data) < 20 & nrow(data) > 2){
      warning("Subset has less than 20 rows, averages may be problematic.")
    }
  }
  if(nrow(data) <3 & !missing(varList)){
    warning("Subset has fewer than 3 rows, computing global average instead.")
    data <- merMod@frame
  }
  out <- collapseFrame(data)
  reTerms <- names(ngrps(merMod))
  for(i in 1:length(reTerms)){
    out[, reTerms[i]] <- findREquantile(model = merMod,
                                        quantile = 0.5, group = reTerms[[i]])
    out[, reTerms[i]] <- as.character(out[, reTerms[i]])
  }
  chars <- !sapply(out, is.numeric)
  for(i in names(out[, chars])){
    out[, i] <- superFactor(out[, i], fullLev = unique(merMod@frame[, i]))
  }
  out <- stripAttributes(out)
  return(out)
}


#' @title Create a factor with unobserved levels
#' @name superFactor
#' @description Create a factor variable and include unobserved levels
#' for compatibility with model prediction functions
#' @param x a vector to be converted to a factor
#' @param fullLev a vector of factor levels to be assigned to x
#' @return a factor variable with all observed levels of x and all levels
#' of x in fullLev
#' @export
superFactor <- function(x, fullLev){
  x <- as.character(x)
  if(class(fullLev) == "factor"){
    fullLev <- unique(levels(fullLev))
  }
  x <- factor(x, levels = c(fullLev),
              labels = c(fullLev))
  return(x)
}

#' @title Randomly reorder a dataframe
#' @name shuffle
#' @description Randomly reorder a dataframe by row
#' @param data a data frame
#' @return a data frame of the same dimensions with the rows reordered
#' randomly
shuffle <- function(data){
  return(data[sample(nrow(data)),])
}

#' @title Assign an observation to different values
#' @name wiggleObs
#' @description Creates a new data.frame with copies of the original observation,
#' each assigned to a different user specified value of a variable. Allows the
#' user to look at the effect of changing a variable on predicted values.
#' @param data a data frame with one or more observations to be reassigned
#' @param var a character specifying the name of the variable to adjust
#' @param values a vector with the variables to assign to var
#' @return a data frame with each row in data assigned to all values for
#' the variable chosen
#' @export
wiggleObs <- function(data, var, values){
  tmp.data <- data
  while(nrow(data) < length(values) * nrow(tmp.data)){
    data <- rbind(data, shuffle(tmp.data))
  }
  data[, var] <- values
  #   data[, var] <- factor(data[, var])
  return(sanitizeNames(data))
}

#' @title Identify group level associated with RE quantile
#' @name findREquantile
#' @description For a user specified quantile (or quantiles) of the random effect
#' terms in a merMod object. This allows the user to easily identify the obsevation
#' associated with the nth percentile effect.
#' @param merMod a merMod object with one or more random effect levels
#' @param quantile a numeric vector with values between 0 and 1 for quantiles
#' @param group a character of the name of the random effect group to extract
#' quantiles from
#' @param eff a character of the random effect to extract for the grouping term
#' specified. Default is the intercept.
#' @return a vector of the level of the random effect grouping term that corresponds
#' to each quantile
#' @export
findREquantile <- function(merMod, quantile, group, eff = "(Intercept)"){
  myRE <- ranef(merMod)[[group]]
  myRE <- myRE[order(-myRE[, eff]), ,drop = FALSE]
  nobs <- nrow(myRE)
  obsnum <- floor(quantile * nobs/100)
  return(rownames(myRE)[obsnum])
}