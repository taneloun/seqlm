\name{tissue_small}
\alias{artificial}
\alias{tissue_small}
\title{\code{tissue_small} contains a subset of tissue panel samples corresponding
 to adipose tissue and lower part of the brainstem \emph{medulla oblongata}.
 To make the data size manageable, this dataset contains only the data from
 17 and 18 cromosome. The data is generated using Illumina 450K platform.}
\description{
  The \code{tissue_small} dataset is a list with 3 slots
  \enumerate{ \item \code{values} - beta value matrix;
  \item \code{genome_information} - the probe annotations
  in the required GRanges format; \item \code{annotation} -
  a vector with sample annotations. }
}
\details{
  \code{artificial} is a very small generated example to
  test the basic functionality of seqlm. It is also a list
  and contains same also \code{values} and
  \code{genome_information} slots but instead of
  \code{annotation} slot there are two different vectors
  \code{annotation1} and \code{annotation2}.
}
\author{
  Raivo Kolde <rkolde@gmail.com>
}
\references{
  Lukk M, Kapushesky M, Nikkila J, Parkinson H, Goncalves
  A, Huber W, Ukkonen E, Brazma A. "A global map of human
  gene expression." Nat Biotechnology. 2010
  Apr;28(4):322-4.
}
\keyword{data}

