# TODO: Ultimately, combine() is just a special case of combineList(), so
#       should simplify code
setMethod("combine", signature(x = "BSseq", y = "BSseq"), function(x, y, ...) {
    ## All of this assumes that we are place x and y "next" to each other,
    ##  ie. we are not combining the same set of samples sequenced at different times
    if (class(x) != class(y)) {
        stop(paste("objects must be the same class, but are ",
                   class(x), ", ", class(y), se = ""))
    }
    if (hasBeenSmoothed(x) && hasBeenSmoothed(y) &&
        !all.equal(getBSseq(x, "trans"), getBSseq(y, "trans")) &&
        !all.equal(getBSseq(x, "parameters"), getBSseq(y, "parameters"))) {
        stop("'x' and 'y' need to be smoothed on the same scale")
    }
    pData <- combine(as(pData(x), "data.frame"), as(pData(y), "data.frame"))
    # TODO: Could relax this by sorting x and y before doing the next steps
    if (identical(granges(x), granges(y))) {
        # NOTE: Don't realize() M, Cov, coef, or se.coef because we are
        #       cbind()-ing, which is very efficient for DelayedArray objects.
        #       E.g., cbind()-ing a bunch of HDF5Matrix objects is super fast
        #       and uses basically no memory whereas realize()-ing the final
        #       object as a new HDF5Matrix can take a long time.
        gr <- granges(x)
        M <- cbind(getBSseq(x, "M"), getBSseq(y, "M"))
        Cov <- cbind(getBSseq(x, "Cov"), getBSseq(y, "Cov"))
        if (!hasBeenSmoothed(x) || !hasBeenSmoothed(y)) {
            coef <- NULL
            se.coef <- NULL
            trans <- NULL
            parameters <- NULL
        } else {
            x_trans <- getBSseq(x, "trans")
            y_trans <- getBSseq(y, "trans")
            if (!identical(x_trans, y_trans)) {
                stop("'x' and 'y' need to have the same 'trans'")
            }
            trans <- x_trans
            x_parameters <- getBSseq(x, "parameters")
            y_parameters <- getBSseq(y, "parameters")
            if (!identical(x_parameters, y_parameters)) {
                stop("'x' and 'y' need to have the same 'parameters'")
            }
            parameters <- x_parameters
            coef <- cbind(getBSseq(x, "coef"), getBSseq(y, "coef"))
            if (!is.null(getBSseq(x, "se.coef")) &&
                !is.null(getBSseq(y, "se.coef"))) {
                se.coef <- cbind(getBSseq(x, "se.coef"), getBSseq(y, "se.coef"))
            } else {
                if (!is.null(getBSseq(x, "se.coef")) ||
                    !is.null(getBSseq(y, "se.coef"))) {
                    warning("Setting 'se.coef' to NULL: Cannot combine() ",
                            "these because one of 'x' or 'y' is missing ",
                            "'se.coef'")
                    }
                se.coef <- NULL
            }
        }
    } else {
        gr <- reduce(c(granges(x), granges(y)), min.gapwidth = 0L)
        mm.x <- as.matrix(findOverlaps(gr, granges(x)))
        mm.y <- as.matrix(findOverlaps(gr, granges(y)))
        I <-  list(mm.x[, 1], mm.y[, 1])
        ## FIXME: there is no check that the two sampleNames are disjoint.
        sampleNames <- c(sampleNames(x), sampleNames(y))
        M_X <- list(getBSseq(x, "M"), getBSseq(y, "M"))
        if (any(vapply(M_X, .isHDF5ArrayBacked, logical(1L)))) {
            M_BACKEND <- "HDF5Array"
        } else {
            M_BACKEND <- NULL
        }
        # TODO: Figure out if fill should be 0 or 0L based on M_X
        M <- .combineListOfDelayedMatrixObjects(
            X = M_X,
            I = I,
            nrow = length(gr),
            ncol = length(sampleNames),
            dimnames = list(NULL, sampleNames),
            fill = 0L,
            BACKEND = M_BACKEND)
        Cov_X <- list(getBSseq(x, "Cov"), getBSseq(y, "Cov"))
        if (any(vapply(Cov_X, .isHDF5ArrayBacked, logical(1L)))) {
            Cov_BACKEND <- "HDF5Array"
        } else {
            Cov_BACKEND <- NULL
        }
        Cov <- .combineListOfDelayedMatrixObjects(
            X = list(getBSseq(x, "Cov"), getBSseq(y, "Cov")),
            I = I,
            nrow = length(gr),
            ncol = length(sampleNames),
            dimnames = list(NULL, sampleNames),
            fill = 0L,
            BACKEND = Cov_BACKEND)
        if (hasBeenSmoothed(x) || hasBeenSmoothed(y)) {
            warning("Setting 'coef' and 'se.coef' to NULL: Cannot combine() ",
                    "these because 'x' and 'y' have different rowRanges")
        }
        coef <- NULL
        se.coef <- NULL
        trans <- NULL
        parameters <- NULL
    }
    BSseq(gr = gr, M = M, Cov = Cov, coef = coef, se.coef = se.coef,
          pData = pData, trans = trans, parameters = parameters,
          rmZeroCov = FALSE)
})

combineList <- function(x, ..., BACKEND = NULL) {
    if (class(x) == "BSseq") {
        x <- list(x, ...)
    }
    stopifnot(all(sapply(x, class) == "BSseq"))
    trans <- getBSseq(x[[1]], "trans")
    sameTrans <- sapply(x[-1], function(xx) {
        identical(trans, getBSseq(xx, "trans"))
    })
    if (!all(sameTrans)) {
        stop("all elements of '...' in combineList needs to have the same ",
             "'trans'")
    }
    parameters <- getBSseq(x[[1]], "parameters")
    same_parameters <- vapply(x, function(xx) {
        identical(getBSseq(xx, "parameters"), parameters)
    }, logical(1L))
    if (!all(same_parameters)) {
        stop("all elements of '...' in combineList needs to have the same ",
             "'parameters'")
    }
    # TODO: Could relax this by sorting all elements of x before doing the
    #       next steps
    gr <- getBSseq(x[[1]], "gr")
    sameGr <- sapply(x[-1], function(xx) {
        identical(gr, getBSseq(xx, "gr"))
    })
    if (all(sameGr)) {
        # NOTE: Don't realize() M, Cov, coef, or se.coef because we are
        #       cbind()-ing, which is very efficient for DelayedArray objects.
        #       E.g., cbind()-ing a bunch of HDF5Matrix objects is super fast
        #       and uses basically no memory whereas realize()-ing the final
        #       object as a new HDF5Matrix can take a long time.
        M <- do.call(cbind, lapply(x, function(xx) getBSseq(xx, "M")))
        Cov <- do.call(cbind, lapply(x, function(xx) getBSseq(xx, "Cov")))
        if (any(!vapply(x, hasBeenSmoothed, logical(1L)))) {
            warning("Setting 'coef' and 'se.coef' to NULL: Cannot combine() ",
                    "these because BSseq objects have different rowRanges")
            coef <- NULL
            se.coef <- NULL
            trans <- NULL
        } else {
            list_of_trans <- lapply(x, getBSseq, "trans")
            if (!all(vapply(list_of_trans, function(trans) {
                identical(trans, list_of_trans[[1]])
            }, logical(1L)))) {
                stop("All BSseq objects need to have the same 'trans'")
            }
            trans <- list_of_trans[[1]]
            list_of_parameters <- lapply(x, getBSseq, "parameters")
            if (!all(vapply(list_of_parameters, function(parameters) {
                identical(parameters, list_of_parameters[[1]])
            }, logical(1L)))) {
                stop("All BSseq objects need to have the same 'parameters'")
            }
            parameters <- list_of_parameters[[1]]
            list_of_coef <- lapply(x, function(xx) getBSseq(xx, "coef"))
            coef <- do.call(cbind, list_of_coef)
            list_of_se.coef <- lapply(x, function(xx) getBSseq(xx, "se.coef"))
            if (all(!vapply(list_of_coef, is.null, logical(1L)))) {
                se.coef <- do.call(cbind, list_of_se.coef)
            } else {
                if (any(vapply(list_of_coef, is.null, logical(1L)))) {
                    warning("Setting 'se.coef' to NULL: Cannot combine() ",
                            "these because at least of the BSseq objects ",
                            "is missing 'se.coef'")
                }
                se.coef <- NULL
            }
        }
    } else {
        gr <- sort(reduce(do.call(c, unname(lapply(x, granges))),
                          min.gapwidth = 0L))
        I <- lapply(x, function(xx) {
            ov <- findOverlaps(gr, xx)
            queryHits(ov)
        })
        sampleNames <- do.call(c, unname(lapply(x, sampleNames)))
        ## FIXME: there is no check that the sampleNames are unique/disjoint.
        # TODO: Figure out if fill should be 0 or 0L based on X (getting it
        #       right will avoid a copy/cast)
        M <- .combineListOfDelayedMatrixObjects(
            X = lapply(x, getBSseq, "M"),
            I = I,
            nrow = length(gr),
            ncol = length(sampleNames),
            dimnames = list(NULL, sampleNames),
            fill = 0,
            BACKEND = BACKEND)
        Cov <- .combineListOfDelayedMatrixObjects(
            X = lapply(x, getBSseq, "Cov"),
            I = I,
            nrow = length(gr),
            ncol = length(sampleNames),
            dimnames = list(NULL, sampleNames),
            fill = 0,
            BACKEND = BACKEND)
        if (any(vapply(x, hasBeenSmoothed, logical(1L)))) {
            warning("Setting 'coef' and 'se.coef' to NULL: Cannot combine() ",
                    "these because BSseq objects have different rowRanges")
        }
        coef <- NULL
        se.coef <- NULL
        trans <- NULL
    }
    pData <- as(Reduce(combine,
                       lapply(x, function(xx) as.data.frame(pData(xx)))),
                "DataFrame")
    BSseq(gr = gr, M = M, Cov = Cov, coef = coef, se.coef = se.coef,
          pData = pData, trans = trans, parameters = parameters,
          rmZeroCov = FALSE)
}
