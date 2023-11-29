#!bin/env/python

import networkx as nx
import matplotlib.pyplot as plt
import pandas as pd
from IPython.display import display
# import random


df = pd.read_csv('../data/edges.csv', skiprows=1, header=None)
# display(df)
edges = [tuple(x) for x in df.values]
G = nx.Graph()
G.add_edges_from(edges)

betweenness = nx.betweenness_centrality(G)
betweeness_nodes = sorted(betweenness.items(), key=lambda x: x[1], reverse=True)

def targeted_attack(G, sorted_nodes):
    LCC={} #key represent the number of nodes removed, value represent the size of the LCC
    for i in range(len(sorted_nodes)):
        G.remove_node(n)
        #sav ethe size of the LCC
        size_of_LCC = len(max(nx.connected_components(G), key=len))  
        LCC[i] = size_of_LCC