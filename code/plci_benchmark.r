# code from https://github.com/drguilbe/complexpaths
# code file: calculate_complex_path_length_and_centrality_first_release.R
# Guilbeault, D., & Centola, D. (2021). Topological measures for identifying and predicting the spread of complex contagions. Nature communications, 12(1), 4430.


#Load Libraries
rm(list=ls());gc()
library(dplyr)
library(tidyr)
library(influential)
library(fastnet)
library(igraph)
library(doParallel)
library(parallel)

#Model Functions
min_max_norm<-function(x){(x - min(x,na.rm=TRUE))/(max(x,na.rm=TRUE) - min(x,na.rm=TRUE))}

clustered_seeding<-function(seeds, g, seeds_needed){
  possible_seeds<-unique(unlist(sapply(seeds, function(x) neighbors(g, x, mode = "total"))))
  seeds_to_add<-possible_seeds[!possible_seeds %in% seeds]
  need_seeds<-seeds_needed > length(seeds_to_add)
  if(need_seeds){return(possible_seeds)}
  else{final_seeds<-c(seeds, sample(seeds_to_add, seeds_needed))
  return(final_seeds)
  }
}

get_simple_centralities<-function(g){
  centrality_df<-data.frame(seed=(V(g)), degree = as.numeric(degree(g)), betweenness = as.numeric(betweenness(g)), eigen = as.numeric(eigen_centrality(g)$vector)) 
  percolation<-collective.influence(graph=g, vertices = V(g), mode="all", d=3)
  centrality_df$percolation<-as.numeric(percolation); 
  return(centrality_df)
}

get_complex<-function(seed, N, g, gmat, thresholds, num_seeds_to_add, model_output_list){
  gmat_simulation<-matrix(nrow=N,ncol=N,0)
  num_seeds_i<-num_seeds_to_add[seed]
  seeds_to_add<-numeric(num_seeds_i)
  
  if(num_seeds_i > 0){
    seeds<-as.numeric(neighbors(g, seed, mode = "total")) 
    num_seeds_needed<-num_seeds_i - length(seeds)
    need_seeds<-num_seeds_needed > 0 
    if(need_seeds){#initiate clustered Seeding
      seeds<-clustered_seeding(seeds, g, num_seeds_needed)
      num_seeds_needed<-num_seeds_i - length(seeds)
      need_seeds<-num_seeds_needed > 0}else if(length(seeds)>1){
        seeds<-c(seed, sample(seeds,num_seeds_i))
      }else{
        seeds<-c(seed, seeds)
      }
  }
  
  activated<-logical(N); activated[seeds]<-TRUE
  gmat_simulation[seeds,]<-1; gmat_simulation[,seeds]<-1
  gmat_simulation_run<-gmat*gmat_simulation
  
  spread=TRUE
  while(spread){
    influence<-colSums(gmat_simulation_run)
    influence_activated<-influence>=thresholds
    t<-which(activated)
    t_1<-which(influence_activated)
    t_full<-union(t,t_1)
    spread<-length(t_full)>length(t)
    activated[t_full]<-TRUE
    adopters<-which(activated)
    gmat_simulation[adopters,]<-1
    gmat_simulation[,adopters]<-1
    gmat_simulation_run<-gmat*gmat_simulation
  }

  num_adopters<-sum(activated)
  complex_g<-graph_from_adjacency_matrix(gmat_simulation_run)
  all_distances<-distances(complex_g, seed, V(complex_g), mode="out")
  all_distances[all_distances == "Inf"]<-0
  PLci<-mean(all_distances)
  
  model_output_list<-c(seed, N, num_seeds_i, num_adopters, PLci)

  return(model_output_list)
}


#####################################
##Model without Parallel Processing##
#####################################


# N<-200
# g<-net.holme.kim(N,4,0.5)
# g<-to.igraph(g)

#read graph from ../data/edges.csv where there is only edges besides the header
# g <- read_graph("../data/edges.csv", format = "edgelist", directed = FALSE, skip = 1)

# df <- read.csv("../data/edges.csv", header = TRUE)
# Create a graph from the data frame
# g <- graph_from_data_frame(df, directed = FALSE)




#------------------------------------

my_dir_files <- list.files("benchmark", pattern = "*.gml", full.names = TRUE)

for (f in my_dir_files){
  base_name <- basename(f)
  graph_name <- gsub("\\.gml$", "", base_name)
  graph_name <- gsub("-", "_", graph_name)
  print(graph_name)

  g<-read_graph(f, format = 'gml')
  N <- vcount(g)
  cat("graph has ", N, " nodes\n")

  gmat<-as.matrix(as_adjacency_matrix(g))
  T_dist<-c("homo", "hetero")[1]
  T_type<-c("abs","frac")[1]
  thresholds<-replicate(N, 3)
  #thresholds<-replicate(N, runif(1, 0.1,0.5)) #fractional Ts distributed uniformly at random. 
  if(T_type == "frac"){thresholds = round(unlist(lapply(1:N, function(x) thresholds[x] * length(neighbors(g, x, mode = "total")))))}
  num_seeds_to_add<-thresholds-1
  num_seeds_to_add[num_seeds_to_add<0]=0
  thresholds[thresholds<=0]=1
  simple_centralities_df<-get_simple_centralities(g)

  #Run Model
  model_output_list <- vector(mode = "list", length = N)
  start_time <- proc.time()
  model_output_list<-lapply(1:N, function(x) get_complex(x, N, g, gmat, thresholds, num_seeds_to_add, model_output_list)) #Run model; change 1:N to any subset of specific seeds to narrow search
  print(proc.time() - start_time) #view runtime 
  model_output_df <- as.data.frame(Reduce(rbind, model_output_list))
  colnames(model_output_df)<-c("seed","N","num_neigh_seeds", "num_adopters","PLci")
  model_output_df$PLci_norm<-min_max_norm(model_output_df$PLci)
  model_output_full<-merge(model_output_df, simple_centralities_df, by="seed") #map to simple centralities of seed

  model_output_full
  plci <- model_output_full$PLci
  print(paste("max plci is for node #", which.max(plci)))

  print(paste("max percolation is for node #", which.max(model_output_full$percolation)))
  print(paste("max norm plci is for node #", which.max(model_output_full$PLci_norm)))

  #put me the resulting df ina  csv file



  # Get the vertices of the graph
  vertices <- as.data.frame(V(g))
  #make the rownames as columns
  vertices$y <- rownames(vertices)
  write.csv(vertices, file = "vertices_test.csv", row.names = TRUE)

  #merge the vertices with the model output based on seed and rownames
  model_output_full <- merge(model_output_full, vertices, by.x = "seed", by.y = "x")
  model_output_full

  #take only the 1st,5th and 9th columns
  model_output_test <- model_output_full[c(1,5,10)]
  csv_name <- paste("plci_results/", graph_name, ".csv", sep = "")
  write.csv(model_output_test, csv_name, row.names = FALSE)
}