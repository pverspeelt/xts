#
#   xts: eXtensible time-series 
#
#   Copyright (C) 2008  Jeffrey A. Ryan jeff.a.ryan @ gmail.com
#
#   Contributions from Joshua M. Ulrich
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.


merge.xts <- function(..., 
                     all=TRUE,
                     fill=NA,
                     suffixes=NULL,
                     join="outer",
                     retside=TRUE,
                     retclass="xts",
                     tzone=NULL,
                     drop=NULL,
                     check.names=NULL) {
  if(is.logical(retclass) && !retclass) {
    setclass=FALSE
  } else setclass <- TRUE

  fill.fun <- NULL
  if(is.function(fill)) {
    fill.fun <- fill 
    fill <- NA
  } 
  
  # as.list(substitute(list(...)))  # this is how zoo handles colnames - jar
  mc <- match.call(expand.dots=FALSE)
  dots <- mc$...
  if(is.null(suffixes)) {
    syms <- names(dots)
    syms[nchar(syms)==0] <- as.character(dots)[nchar(syms)==0]
    if(is.null(syms)) syms <- as.character(dots)
  } else
  if(length(suffixes) != length(dots)) {
    warning("length of suffixes and does not match number of merged objects")
    syms <- as.character(dots)
  } else {
    syms <- as.character(suffixes)
    sfx  <- as.character(suffixes)
  }

  .times <- .External('number_of_cols', ..., PACKAGE="xts")
  symnames <- rep(syms, .times)  # moved call to make.names inside of mergeXts/do_merge_xts

  if(length(dots) == 1) {
    # this is for compat with zoo; one object AND a name
    if(!is.null(names(dots))) {
      x <- list(...)[[1]]
      if(is.null(colnames(x))) 
        colnames(x) <- symnames
      return(x)
    }
  }

  if( !missing(join) ) { 
    # join logic applied to index:
    # inspired by: http://blogs.msdn.com/craigfr/archive/2006/08/03/687584.aspx
    #   
    #  (full) outer - all cases, equivelant to all=c(TRUE,TRUE)
    #         left  - all x,    &&  y's that match x
    #         right - all  ,y   &&  x's that match x
    #         inner - only x and y where index(x)==index(y)
    all <- switch(pmatch(join,c("outer","left","right","inner")),
                    c(TRUE,  TRUE ), #  outer
                    c(TRUE,  FALSE), #  left
                    c(FALSE, TRUE ), #  right
                    c(FALSE, FALSE)  #  inner
                 )   
    if( length(dots) > 2 ) {
      all <- all[1]
      warning("'join' only applicable to two object merges")
    }
  }

  if( length(all) != 2 ) {
    if( length(all) > 2 )
      warning("'all' must be of length two")
    all <- rep(all[1], 2)
  }
  if( length(dots) > 2 )
    retside <- TRUE
  if( length(retside) != 2 ) 
    retside <- rep(retside[1], 2)

  x <- .External('mergeXts',
            all=all[1:2],
            fill=fill,
            setclass=setclass,
            symnames=symnames,
            suffixes=suffixes,
            retside=retside,
            env=new.env(),
            tzone=tzone,
            ..., PACKAGE="xts")
  if(!is.logical(retclass) && retclass != 'xts') {
    asFun <- paste("as", retclass, sep=".")
    if(!exists(asFun)) {
      warning(paste("could not locate",asFun,"returning 'xts' object instead"))
      return(x)
    }
    xx <- try(do.call(asFun, list(x)))
    if(!inherits(xx,'try-error')) {
      return(xx)
    }
  }
  if(!is.null(fill.fun)) {
    fill.fun(x)
  } else
  return(x)
}
.merge.xts <- function(x,y,...,
                      all=TRUE,
                      fill=NA,
                      suffixes=NULL,
                      join="outer",
                      retside=TRUE,
                      retclass="xts") {

  if(missing(y))
    return(x)
  if(is.logical(retclass) && !retclass) {
    setclass <- FALSE
  } else setclass <- TRUE

  mc <- match.call(expand.dots=FALSE)
  xName <- deparse(mc$x)
  yName <- deparse(mc$y)
  dots <- mc$...

  if(!missing(...) && length(all) > 2) {
    xx <- list(x,y,...)
    all <- rep(all, length.out=length(xx))
    if(!base::all(all==TRUE) && !base::all(all==FALSE) ) {
      xT <- xx[which(all)] 
      xF <- xx[which(!all)] 
      return((rmerge0(do.call('rmerge0',xT),
                      do.call('rmerge0',xF), join="left"))[,c(which(all),which(!all))])
    }
  }

  tryXts <- function(y) {
  if(!is.xts(y)) {
    y <- try.xts(y, error=FALSE)
    if(!is.xts(y)) {
      if (NROW(y) == NROW(x)) {
        y <- structure(y, index = .index(x))
      }
      else if (NROW(y) == 1 && NCOL(y) == 1) {
        y <- structure(rep(y, length.out = NROW(x)), index = .index(x))
      }
      else stop(paste("cannot convert", deparse(substitute(y)), 
        "to suitable class for merge"))
    }
  }
  return(y)
  }


  if( !missing(join) ) { 
    # join logic applied to index:
    # inspired by: http://blogs.msdn.com/craigfr/archive/2006/08/03/687584.aspx
    #   
    #  (full) outer - all cases, equivelant to all=c(TRUE,TRUE)
    #         left  - all x,    &&  y's that match x
    #         right - all  ,y   &&  x's that match x
    #         inner - only x and y where index(x)==index(y)
    all <- switch(pmatch(join,c("outer","left","right","inner")),
                    c(TRUE,  TRUE ), #  outer
                    c(TRUE,  FALSE), #  left
                    c(FALSE, TRUE ), #  right
                    c(FALSE, FALSE)  #  inner
                 )   
  }

  makeUnique <- function(cnames, nc, suff, dots) {
    if(is.null(suff) || length(suff) != (length(dots)+2)) return(make.unique(cnames))
    paste(cnames, rep(suff, times=nc),sep=".")
  }

  if( length(all) == 1 ) 
    all <- rep(all, length.out=length(dots)+2)
  if( length(retside) == 1 ) 
    retside <- rep(retside, length.out=length(dots)+2)

  y <- tryXts(y)

  COLNAMES <- c(colnames(x),colnames(y))
  if(length(COLNAMES) != (NCOL(x)+NCOL(y)))
    COLNAMES <- c(rep(xName,NCOL(x)), rep(yName,NCOL(y)))

  xCOLNAMES <- colnames(x)
  if(is.null(xCOLNAMES))
    xCOLNAMES <- rep(xName,NCOL(x))
  yCOLNAMES <- colnames(y)
  if(is.null(yCOLNAMES))
    yCOLNAMES <- rep(yName,NCOL(y))
  COLNAMES <- c(xCOLNAMES,yCOLNAMES)

  nCOLS <- c(NCOL(x), NCOL(y), sapply(dots, function(x) NCOL(eval.parent(x))))
  CNAMES <- if(length(dots)==0) {
              makeUnique(COLNAMES, nCOLS, suffixes, dots)
            } else NULL
 
  x <- .Call("do_merge_xts",
              x, y, all, fill[1], setclass, CNAMES, retside, PACKAGE="xts")
  if(length(dots) > 0) {
    for(i in 1:length(dots)) {
      currentCOLNAMES <- colnames(eval.parent(dots[[i]]))
      if(is.null(currentCOLNAMES))
        currentCOLNAMES <- rep(deparse(dots[[i]]),NCOL(eval.parent(dots[[i]])))
      COLNAMES <- c(COLNAMES, currentCOLNAMES)

      if( i==length(dots) ) #last merge, set colnames now
        CNAMES <- makeUnique(COLNAMES, nCOLS, suffixes, dots)
      x <- .Call("do_merge_xts",
                  x, tryXts(eval.parent(dots[[i]])), all,
                  fill[1], setclass, CNAMES, retside, PACKAGE="xts")
  
    }
  }
if(!is.logical(retclass) && retclass != 'xts') {
  xx <- try(do.call(paste("as",retclass,sep="."), list(x)))
  if(!inherits(xx,'try-error')) {
    return(xx)
  }
}
return(x)
}

rmerge0 <- function(x,y,...,
                   all=TRUE,
                   fill=NA,
                   suffixes=NULL,
                   join="outer",
                   retside=TRUE,
                   retclass="xts") {

  if(missing(y) || is.null(y))
    return(x)
  if(is.logical(retclass) && !retclass) {
    setclass <- FALSE
  } else setclass <- TRUE

  mc <- match.call(expand.dots=FALSE)
  xName <- deparse(mc$x)
  yName <- deparse(mc$y)
  dots <- mc$...

#  if(!missing(...) && length(all) > 2) {
#    x <- list(x,y,...)
#    all <- rep(all, length.out=length(x))
#    xT <- x[which(all)] 
#    xF <- x[which(!all)] 
#    return((rmerge0(do.call('rmerge0',xT), do.call('rmerge0',xF), join="left"))[,c(which(all),which(!all))])
#  }

  tryXts <- function(y) {
  if(!is.xts(y)) {
    y <- try.xts(y, error=FALSE)
    if(!is.xts(y)) {
      if (NROW(y) == NROW(x)) {
        y <- structure(y, index = .index(x))
      }
      else if (NROW(y) == 1 && NCOL(y) == 1) {
        y <- structure(rep(y, length.out = NROW(x)), index = .index(x))
      }
      else stop(paste("cannot convert", deparse(substitute(y)), 
        "to suitable class for merge"))
    }
  }
  return(y)
  }


  if( !missing(join) ) { 
    # join logic applied to index:
    # inspired by: http://blogs.msdn.com/craigfr/archive/2006/08/03/687584.aspx
    #   
    #  (full) outer - all cases, equivelant to all=c(TRUE,TRUE)
    #         left  - all x,    &&  y's that match x
    #         right - all  ,y   &&  x's that match x
    #         inner - only x and y where index(x)==index(y)
    all <- switch(pmatch(join,c("outer","left","right","inner")),
                    c(TRUE,  TRUE ), #  outer
                    c(TRUE,  FALSE), #  left
                    c(FALSE, TRUE ), #  right
                    c(FALSE, FALSE)  #  inner
                 )   
  }

  makeUnique <- function(cnames, nc, suff, dots) {
    if(is.null(suff) || length(suff) != (length(dots)+2)) return(make.unique(cnames))
    paste(cnames, rep(suff, times=nc),sep=".")
  }

  if( length(all) == 1 ) 
    all <- rep(all, length.out=length(dots)+2)
  if( length(retside) == 1 ) 
    retside <- rep(retside, length.out=length(dots)+2)
  y <- tryXts(y)

  COLNAMES <- c(colnames(x),colnames(y))
  if(length(COLNAMES) != (NCOL(x)+NCOL(y)))
    COLNAMES <- c(rep(xName,NCOL(x)), rep(yName,NCOL(y)))

  xCOLNAMES <- colnames(x)
  if(is.null(xCOLNAMES))
    xCOLNAMES <- rep(xName,NCOL(x))
  yCOLNAMES <- colnames(y)
  if(is.null(yCOLNAMES))
    yCOLNAMES <- rep(yName,NCOL(y))
  COLNAMES <- c(xCOLNAMES,yCOLNAMES)

  nCOLS <- c(NCOL(x), NCOL(y), sapply(dots, function(x) NCOL(eval.parent(x))))
#  CNAMES <- if(length(dots)==0) {
#              makeUnique(COLNAMES, nCOLS, suffixes, dots)
#            } else NULL
  CNAMES <- NULL
 

  x <- .Call("do_merge_xts",
              x, y, all, fill[1], setclass, CNAMES, retside, PACKAGE="xts")
  if(length(dots) > 0) {
    for(i in 1:length(dots)) {
      currentCOLNAMES <- colnames(eval.parent(dots[[i]]))
      if(is.null(currentCOLNAMES))
        currentCOLNAMES <- rep(deparse(dots[[i]]),NCOL(eval.parent(dots[[i]])))
      COLNAMES <- c(COLNAMES, currentCOLNAMES)

#      if( i==length(dots) ) #last merge, set colnames now
#        CNAMES <- makeUnique(COLNAMES, nCOLS, suffixes, dots)
      x <- .Call("do_merge_xts",
                  x, tryXts(eval.parent(dots[[i]])), all,
                  fill[1], setclass, CNAMES, retside, PACKAGE="xts")
  
    }
  }
return(x)
}
#library(xts)
#x <- .xts(1:10, 1:10)
#rmerge(x,x,x)
#rmerge(x,x,1)
#z <- as.zoo(x)
#rmerge(x,z)
#rmerge(x,x,z)
#rmerge(x,1,z,z)
#X <- .xts(1:1e6, 1:1e6)
#system.time(rmerge(X,X,X,X,X,X,X))
