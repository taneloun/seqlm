## lm based description length functions
row_subsets = function(mat, k){
	n = ncol(mat)
	m = nrow(mat)
	
	if(k == 1){
		res = t(mat)
	}
	else{
		res = matrix(NA, n * k, m - k + 1)
		for(i in 1:(m - k + 1)){
			res[, i] = as.vector(t(mat[i:(i + k - 1), ]))
		}
	}
	
	return(res)
}

vars = function(rss, n, df, n0, sig0){
	s = ((n0 * sig0 + n * rss / df) / (n0 + n))
	v = n0 + n
	
	var = (v * s) / (v - 2)
	
	return(var)
}

calculate_rss = function(fit){
	if (is.matrix(fit$residuals)){
		rss = apply(fit$residuals, 2, function(r) sum(r * r))
	}
	else{
		rss = sum(fit$residuals * fit$residuals)
	}
	return(rss)
}

number_of_coefs = function(fit){
	if (is.matrix(fit$residuals)){
		n = nrow(fit$residuals)
	}
	else{
		n = length(fit$residuals)
	}
	return(n)
}

row_bics = function(fit, n0,  m0, sig0, alpha){
	k = fit$rank
	rss = calculate_rss(fit)
	n = number_of_coefs(fit)
	vars = vars(rss, n, fit$df.residual, n0, sig0)

	mdl = ifelse(vars>0, 0.5 * (n*(log2(2*pi) + log2(vars)) + 1/vars/log(2)*rss + alpha*k*log2(m0)), 0.5*alpha*k*log2(m0))
	return(mdl)
}

row_fit = function(mat, annotation, k){
	y = row_subsets(mat, k)
	mm = model.matrix(~ rep(annotation, k))
	
	fit = lm.fit(mm, y)
	
	return(fit)
}

prior_var = function(values, annotation){
	if(nrow(values) > 100){
		values = values[sample(1:nrow(values), 100), ]
	}
	
	f = row_fit(values, annotation, k = 1)
	sig0 = mean(calculate_rss(f) / f$df.residual)
	
	return(sig0)
}

description_length_lm = function(values, annotation, maxlength, n0, m0, sig0, alpha, max_block_length){
	n = ncol(values)
	m = nrow(values)
	
	# Estimate variance
	if(is.na(sig0)){
		sig0 = prior_var(values, annotation)
	}
	
	# Adjust the input priors
	n0 = n * n0
	m0 = n * m0
	
	# Calculate scores
	bics = matrix(NA, m, m)
	m2 = min(m, max_block_length)
	for(i in 1:m2){
		a = row_bics(row_fit(values, annotation, i), n0, m0, sig0, alpha)
		a = a + alpha * log2(maxlength)
		bics[cbind(1 : (m - i + 1), (1 : (m - i + 1)) + i - 1)] = a
	}
	
	return (list("bics" = bics, "max_block_length" = max_block_length))
}
##

## Segmentation related core functions
segmentation = function(inputlist){
	dl = inputlist[[1]]
	max_block_length = inputlist[[2]]
	m = nrow(dl)
	
	# Dynamic programming
	S = rep(0, m + 1)
	I = rep(0, m)

	for(j in 1:m){
		start = ifelse(j>max_block_length, j+1-max_block_length, 1)
		costs = S[start:j] + dl[start:j, j]
		S[j+1] = min(costs)
		i = which.min(costs) + start - 1
		I[j] = i - 1
	}
	
	# Identify Regions
	k = m
	pairs = numeric(0)
	while(k > 0){
		pairs = rbind(pairs, c(I[k] + 1, k))
		k = I[k]
	}
	pairs = as.data.frame(pairs[nrow(pairs):1, , drop=FALSE])
	names(pairs) = c("start", "end")
	return(pairs)
}

group_by_dist = function(pos, max_dist_cpg){
	dist = data.frame("d" = pos[-1] - pos[-length(pos)])
	dist$temp = (dist$d > max_dist_cpg | dist$d < 0)
	indicator = as.factor(c(0, cumsum(dist$temp)))
	
	return (indicator)
}

# Return the number of segmentations
number_of_segmentations = function(lengths, max_block_length){
	if(length(lengths) == 0) return(1)
	
	out = ifelse(lengths <= max_block_length, lengths * (lengths + 1) / 2, max_block_length * (max_block_length + 1) / 2 + max_block_length * (lengths - max_block_length))
	return(out)
}

seqlm_segmentation = function(values, genome_information, max_dist, max_block_length, description_length_par){
	# Center the rows of "values"
	values = t(scale(t(values), center=TRUE, scale=FALSE))
	
	# Divide the genome into initial segments based on genomic coordinate
	chr = IRanges::as.vector(seqnames(genome_information))
	pos = start(genome_information)
	indicator = group_by_dist(pos, max_dist)
	pieces = split(seq_along(indicator), indicator)
	lengths = sapply(pieces, length)
	
	# Sort the pieces by length
	ord = order(-lengths)
	pieces = pieces[ord]
	lengths = lengths[ord]
	
	if(max_block_length > 1){
		# Divide the pieces in two
		which_pieces1 = which(lengths == 1)
		which_pieces2 = which(lengths >= 2)
	}
	else{
		# If max_block_length <= 1 then there is no need to find the segmentation
		which_pieces1 = seq_along(pieces)
		which_pieces2 = c()
	}
	
	# Find cumulative progress for progressbar
	cumprogress = cumsum(number_of_segmentations(lengths[which_pieces2], max_block_length))
	maxProgressBar = cumprogress[length(cumprogress)]

	# Initialize progressbar
	pb <- txtProgressBar(min = 0, max = maxProgressBar, style = 3)
	
	# Check if parallel available
	`%op%` <- if (getDoParRegistered()) `%dopar%` else `%do%`
	
	# Segment based on the model
	maxlength = max(lengths)
	segmentlist = foreach(i = seq_along(which_pieces2), .export=c("description_length_lm", "prior_var", "row_fit", "row_subsets", "row_bics", "vars", "segmentation", "calculate_rss", "number_of_coefs")) %op% {
		# Which rows from the matrix "values" belong to this piece
		u = pieces[[which_pieces2[i]]]
		
		# Set input parameters
		par = description_length_par
		par$values = values[u, , drop=FALSE]
		par$maxlength = maxlength
		par$max_block_length = max_block_length
		
		# Call the partial description length function on whole region
		a = do.call("description_length_lm", par)
		result = segmentation(a)
		
		
		# Advance progressbar
		if (i%%100==0){
			setTxtProgressBar(pb, cumprogress[i])
		}
		
		# In the first column there are "startIndexes", in the second column "endIndexes"
		cbind(u[result$start], u[result$end])
	}
	
	# Finish progressbar 
	setTxtProgressBar(pb, maxProgressBar)
	close(pb)
	
	# Combine foreach results
	res = do.call("rbind", segmentlist)
	
	# Add the pieces with length one
	if(length(which_pieces1) != 0){
		index_pieces1 = unlist(pieces[which_pieces1])
		res = rbind(res, matrix(c(index_pieces1, index_pieces1), ncol=2))
	}
	
	colnames(res) = c("startIndex", "endIndex")
	res = as.data.frame(res)
	res = res[order(res$startIndex), ]
	
	# Generate the genomic ranges object
	segments = GRanges(seqnames = chr[res$startIndex], IRanges(start = pos[res$startIndex], end = pos[res$endIndex]))
	segments@elementMetadata = DataFrame("length" = res$endIndex - res$startIndex + 1, res)
	
	# Compile output
	output = list(
		data = list(
			values = values,
			genome_information = genome_information, 
			annotation = description_length_par$annotation
		),
		description_length_par = description_length_par,
		segments = segments
	)
	
	return (output)
}
##

## Calculate contrasts based on the seqfit output
avg_matrix = function(mat, lengths){
	if(sum(lengths) != nrow(mat)){
		stop("Lengths does not sum up to number of rows in mat")
	}
	
	diag = spMatrix(nrow = length(lengths), ncol = sum(lengths), i = rep(1:length(lengths), lengths), j = 1:sum(lengths), x = 1 / rep(lengths, lengths))
	
	return(as.matrix(diag %*% mat))
}

calculate_t = function(fit){
	Qr = fit$qr
	p = fit$rank
	p1 = p
	if(is.vector(fit$residuals)){
		rss = sum(fit$residuals * fit$residuals)
		est = fit$coefficients[2]
	} 
	else{
		rss = colSums(fit$residuals * fit$residuals)
		est = fit$coefficients[2, ]
	}

	n = NROW(Qr$qr)
	rdf = n - p

	resvar = rss/rdf
	R = chol2inv(Qr$qr[p1, p1, drop = FALSE])
	se = sqrt(diag(R) * resvar)

	tval = est/se

	res = cbind(coef = est, se = se, tstat = tval, p.value = ifelse(is.na(tval), 1, 2 * pt(abs(tval), df=rdf, lower.tail=FALSE)))
	res = data.frame(res)
	
	return(res)
}

seqlm_contrasts = function(seqlmresults){
	segments = seqlmresults$segments
	
	# Calculate p-values
	avg_mat = avg_matrix(seqlmresults$data$values, segments$length)
	fit = row_fit(avg_mat, seqlmresults$data$annotation, 1)
	lm_res = calculate_t(fit)
	
	# Add multile testing p-values
	lm_res$fdr = p.adjust(lm_res$p.value, method = "fdr")
	lm_res$bonferroni = p.adjust(lm_res$p.value, method = "bonferroni")
		
	# Add to the results
	segments@elementMetadata = DataFrame(segments@elementMetadata, lm_res)
	
	return(segments)
}
##


## Accessories for the seqlm function
match_positions = function(values, genome_information){
	# Find intersecting sites
	int = intersect(names(genome_information), rownames(values))
	
	if(is.null(int)){
		stop("Matrix values and genome information have to have the same rownames")
	}
	
	# Extract the intersecting sites from both objects
	genome_information = genome_information[int, ]
	values = values[int, ]
	
	# Order by genomic coordinates
	genome_information = genome_information[order(IRanges::as.vector(seqnames(genome_information)), start(genome_information)), ]
	values = values[names(genome_information), ]
	
	return(list(values = values, genome_information = genome_information))
}

additional_annotation = function(res, df){

	which_numeric = which(sapply(df, is.numeric))
	which_char = setdiff(1:ncol(df), which_numeric)
	
	output_numeric = NULL
	
	cat("\tAll numeric variables\n")
	if(length(which_numeric) > 0){
		numeric_cols = as.matrix(df[, which_numeric, drop=FALSE])
		output_numeric = avg_matrix(numeric_cols, res$length)
		output_numeric = as.list(as.data.frame(output_numeric))
	}
	else{
		output_numeric = list()
	}
	
	output = list()
	startIndexes = res$startIndex
	endIndexes = res$endIndex
	n = length(startIndexes)
	nn = length(res$length > 1) 
	
	for (j in which_char){
		currentData = df[, j]
		cat(sprintf("\tVariable: %s\n", names(df)[j]))
		
		splitted = strsplit(as.character(currentData), ";")
		
		result = rep(NA, n)
		split_lengths = unlist(lapply(splitted, length))
		
		# Case where the length is one and there is only one element that is splitted
		result[res$length == 1 & split_lengths[startIndexes] == 1] = unlist(splitted[startIndexes[res$length == 1 & split_lengths[startIndexes] == 1]])
		
		# Case where length is 1 but several elements are splitted
		result[res$length == 1 & split_lengths[startIndexes] != 1] = unlist(lapply(splitted[startIndexes[res$length == 1 & split_lengths[startIndexes] != 1]], function(x) paste0(unique(x), collapse = ";")))
		
		# Case where length is > 1
		for(i in which(res$length != 1)){
			start = startIndexes[i]
			end = endIndexes[i]
			temp = unique(unlist(splitted[start:end], use.names = F))
			result[i] = paste0(temp[temp!=""], collapse=";")
		}
		output[[j]] = result
	}
	out = as.data.frame(c(output, output_numeric))
	names(out) = names(df)[c(which_char, which_numeric)]
	return(out)
}



#' Sequential lm
#' 
#' Segments genome based on given linear models and and calculates the significance of regions
#' 
#' The analysis can be time consuming if the whole genome is analysed at once.
#'  If the computer has multicore capabilities it is easy to parallelize the 
#' calculations. We use the \code{\link{foreach}}framework by Revolution 
#' Computing for parallelization. To enable the parallelization one has to 
#' register the parallel backend before and this will be used by seqlm.
#' 
#' @param values a matrix where columns are samples and rows correspond to the sites
#' @param genome_information \code{\link{GRanges}} object giving the positions 
#' of the probes, names should correspond to rownames of values. 
#' \code{elementData} of this object is used to annotate the regions 
#' @param annotation vector describing the samples. If discrete then has to have 
#' exactly 2 levels. 
#' @param max_block_length maximal length of the block we are searching. This is 
#' used to speed up computation
#' @param max_dist maximal genomic distance between the sites to be considered the same region
#' @return  A list containing the input data, parameters and the segmentation.
#' 
#' @author  Kaspar Martens <kmartens@@ut.ee> Raivo Kolde <rkolde@@gmail.com>
#' 
#' @examples
#' data(artificial)
#' seqlm(artificial$values, artificial$genome_information, artificial$annotation1)
#' 
#' \dontrun{
#' data(tissue_small)
#' 
#' # Find regions 
#' segments = seqlm(tissue_small$values, tissue_small$genome_information, tissue_small$annotation)
#' 
#' # The calculation can be parallelized by registering a parallel processing backend
#' library(doParallel)
#' registerDoParallel(cores = 2)
#' segments = seqlm(values = tissue_small$values, genome_information = tissue_small$genome_information, annotation =  tissue_small$annotation)
#' 
#' # To visualise the results it is possible to plot the most imortant sites and generate a HTML report
#' temp = tempdir()
#' seqlmreport(segments[1:10], tissue_small$values, tissue_small$genome_information, tissue_small$annotation, dir = temp)
#' 
#' # To see the results open the index.html file generated into the directory temp
#' }
#' @export
seqlm = function(values, genome_information, annotation, max_block_length = 50, max_dist = 1000){
	# Check the input
	if(!inherits(genome_information, "GRanges")){
		stop("genome_information has to be a GRanges object")
	} 
	
	if(!(is.vector(annotation) | is.factor(annotation))){
		stop("annotation has to be a vector")
	}
	
	if(length(annotation) != ncol(values)){
		stop("Number of elements in annotation has to match with the number of columns in values")
	}
	
	if(is.character(annotation) | is.factor(annotation)){
		annotation = factor(annotation)
		if(length(levels(annotation)) != 2){
			stop("If variable annotation is categorical, then it has to have exactly 2 levels")
		}
	}
	
	# Remove rows that contain NAs
	values = values[!apply(is.na(values), 1, any),]
	
	# Match values and genome_information
	mp = match_positions(values, genome_information)
	values = mp$values
	genome_information = mp$genome_information
	
	# Perform segmentation
	cat("Finding the best segmentation\n"); flush.console()
	
	res = seqlm_segmentation(values = values, genome_information = genome_information, max_dist = max_dist, max_block_length = max_block_length, description_length_par = list(annotation = annotation,  n0 = 1, m0 = 10, sig0 = NA, alpha = 2))
		
	# Calculate p-values
	cat("Calculating coefficients and p-values for all regions\n"); flush.console()
	res = seqlm_contrasts(res)
	
	# Add additional annotation
	additionalAnnotation = elementMetadata(genome_information)
	
	if(ncol(additionalAnnotation) != 0){
		cat("Adding additional information to the results\n"); flush.console()
		segment_ann = additional_annotation(res, additionalAnnotation)
		elementMetadata(res) = DataFrame(elementMetadata(res), segment_ann)
	}
	
	# Add probe names 
	names = names(genome_information)
	elementMetadata(res) = DataFrame(elementMetadata(res), probes = apply(cbind(res$startIndex, res$endIndex), 1, function(x) paste0(names[x[1]:x[2]], collapse = ";")))
	
	# Remove startIndex and endIndex
	elementMetadata(res) = elementMetadata(res)[-(2:3)] 
	
	return (res[order(abs(res$tstat), decreasing=TRUE)])
}
##


