#---
#"Projection model for baseline scenario, categorical RSF territory selection method"
#"Lisanne Petracca"
#"April 2025"
#---

library(tidyverse)
library(here)
library(nimble)

######------ PULLING IN FUNCTION, PACKID, OCCUPANCY, CONNECTIVITY, OTHER SPATIAL COMPONENTS ------######

#load categorical RSF territory selection information
load("data/RSF_categorical_territory_selection_information.RData")

#load all functions
source("functions/movement_function.R")
source("functions/removals_function.R")
source("functions/attraction_function.R")
source("functions/translocation_function.R")

#reading in spatial data from projection
load("data/Spatial_Information.RData")

#fixed values 
proj <- 51 #100 #years of projection
nSims <- 100 #number of simulations per sample from the posterior
nSamples <- 500 #number of samples from the posterior,  this has to be set to 500 based on input files
S <- 224 #territories
removal_rate <- 0.04600801 #annual rate based on removals 2012-2020
 
#setting up for new.guys array
newguys <- array(0, dim=c(nSamples,2,proj,S))

####### SCENARIO DESCRIPTIONS ######

#analysis <- "baseline"
#scenario 1: baseline: removal rate at annual mean (0.03510213), immigration as estimated, no harvest, no translocation, no disease

#analysis <- "translocation"
#site <- "Olympic"
#site <- "St Helens"
#scenarios 2-3: translocation of 8 wolves (2 groups of 4; each w/ 2 class 3 adults and 2 6-mo-olds, from E Wash only)
#scenario 2: 8 individuals to sites 10, 14 in the Mt St Helens Elk Herd Area
#scenario 3: 8 individuals to sites 125, 145 on the Olympic Peninsula
#this is happening in fall 2025

#analysis <- "increase removals"
#scenarios 4-5: increase removals such that 30% of population is removed every 4 years
#scenario 4 = all WA, scenario 5 = E Washington only
#this is an increase to a rate of 0.08530878 each year
#1 - (.7 ^ (1/4)) is that calculation
#this increased removal would start in 2023 (year 4)

#analysis <- "harvest"
#scenarios 6-7
#scenario 6: 2.5% removal every 6 mo, additive
#scenario 7: 5% removal every 6 mo, additive
#set harvest level here
#h <- 0.05

#analysis <- "half immigration"
#scenario 8: number of wolves immigrating from out of state reduced by 50%

#analysis <- "no immigration"
#scenario 9: no wolves immigrating from out of state

analysis <- "disease"
#in this scenario, a certain proportion of wolves is removed in two consecutive six-month periods
#scenario 10: 25% loss of population, additive
#scenario 11: 50% loss of population, additive
#scenario 12: 75% loss of population, additive
disease_prop <- 0.25


####### THIS IS WHERE PROJECTION MODEL CODE BEGINS ######

#storage for sim loop
Nglobal_state.mean <- Nglobal_state_wmove.mean <- NAdult_state.mean <-  
  NAdult_EWash.mean <- NAdult_NCasc.mean <- NAdult_SCasc.mean <- 
  NSite_state.mean <- NSite_EWash.mean <- NSite_NCasc.mean <- NSite_SCasc.mean <- array(NA, dim = c(nSamples, proj, nSims))
Lambda.mean <- array(NA, dim = c(nSamples, proj-1, nSims))
BP_Presence <- Pack_Size <- Ntot.site <- Newguys.mean <- Two_Adult <- array(NA, dim = c(nSamples, proj, S, nSims))
lambda.mean <- lambda.upper <- lambda.lower <- p.quasiext <- p.recovery <- numeric(nSims)


for(sim in 1:nSims){
  
  #reading in arrays needed for projection (incl. first year data)
  load("data/Projection_Inputs.RData")   

  set.seed(37585+sim)
  
  #the i loop is inherent here
  #let's start where t==1
  
  for (t in 1:(proj*2-1)) { 
    phiA.proj[,1,t] <- plogis(rnorm(nSamples, mean=int.surv1[,1], sd = sigma.period)) 
    phiA.proj[,2,t] <- plogis(rnorm(nSamples, mean=int.surv1[,1], sd = sigma.period)) 
    phiA.proj[,3,t] <- plogis(rnorm(nSamples, mean=int.surv1[,2], sd = sigma.period)) 
    phiB.proj[,1,t] <- 0
    phiB.proj[,2,t] <- plogis(rnorm(nSamples, mean=int.surv2[,1], sd = sigma.period)) 
    phiB.proj[,3,t] <- plogis(rnorm(nSamples, mean=int.surv2[,2], sd = sigma.period)) 
  } 
  
  if(analysis=="no immigration"){ #this is allowing immigration to start in year 8 (2027)
    #immigration will turn to 0
    lambda.immig.mat <- matrix(NA, nrow=51, ncol=nSamples)
    lambda.immig.mat[1:7,] <- matrix(lambda.immig,nrow=7,ncol=nSamples,byrow=TRUE)
    lambda.immig.mat[8:51,] <- 0 
  }
  
  if(analysis=="half immigration"){
    #immigration will turn to 1/2 of current immigration in 2027
    lambda.immig.mat <- matrix(NA, nrow=51, ncol=nSamples)
    lambda.immig.mat[1:7,] <- matrix(lambda.immig,nrow=7,ncol=nSamples,byrow=TRUE)
    lambda.immig.mat[8:51,] <- matrix(lambda.immig*0.5,nrow=44,ncol=nSamples,byrow=TRUE)
  }
  
  if(analysis=="disease"){
    #let's do it in random year
    time <- sample(c(6:100), 1)
    #disease will take out a certain proportion (25%, 50%, 75%) in two random consecutive 2 mo periods
    phiA.proj[,,time:(time+1)] <- phiA.proj[,,time:(time+1)] * (1-disease_prop)
    phiB.proj[,,time:(time+1)] <- phiB.proj[,,time:(time+1)] * (1-disease_prop)
  }
  
  if(analysis=="harvest"){
    #wait until 2027, then harvest 2.5% or 5% in each 6 month period
    phiA.proj[,,15:(2*proj-1)] <- phiA.proj[,,15:(2*proj-1)] * (1-h) 
    phiB.proj[,,15:(2*proj-1)] <- phiB.proj[,,15:(2*proj-1)] * (1-h)
  }
  
  #####---- STARTING MODEL WITH SECOND PERIOD OF YEAR 1 -----#####
  
  #this is counting Ntot from the first time period [from the IPM output]
  Ntot.proj[,1,] <-
    N.proj[,1,1,1,] + N.proj[,2,1,1,] + N.proj[,3,1,1,]
  
  #moving on to second period of first year now
  for (s in 1:S){ #running through all 224 territories
    
    #12-mo-olds
    #we can actually have 12-mo movers now (edited June 2022 to add epsA)
    N.stayers.proj[,1,2,1,s] <- rbinom(nSamples, N.proj[,1,1,1,s], phiA.proj[,1,1]*(1-epsA[,1]))
    #new line June 2022
    N.movers.proj[,1,2,1,s] <- rbinom(nSamples, N.proj[,1,1,1,s], phiA.proj[,1,1]*epsA[,1]*alpha)
    
    #24-mo-olds
    N.stayers.proj[,2,2,1,s] <- rbinom(nSamples, N.proj[,2,1,1,s], phiA.proj[,2,1]*(1-epsA[,1]))
    #new and old movers - intermediate class - last period's 18-mo old residents survive and start moving but stay in state AND last period's 18-mo old movers continue moving but stay in state 
    #all are 1 here because from same year
    N.movers.newmove.proj[,2,2,1,s] <- rbinom(nSamples, N.proj[,2,1,1,s], phiA.proj[,2,1]*epsA[,1]*alpha) 
    N.movers.oldmove.proj[,2,2,1,s] <- rbinom(nSamples, N.movers.proj[,2,1,1,s], phiB.proj[,2,1]*epsB[,1]*alpha) 
    N.movers.proj[,2,2,1,s] <- N.movers.newmove.proj[,2,2,1,s] + N.movers.oldmove.proj[,2,2,1,s]
    #here are settlers - intermediate class - last periods 18-mo old new movers survive, stop moving, and settle at s  
    N.settlers.proj[,2,2,1,s] <- rbinom(nSamples, N.movers.proj[,2,1,1,s], phiB.proj[,2,1]*(1-epsB[,1]))
    
    #36+-mo-olds
    N.stayers.proj[,3,2,1,s] <- rbinom(nSamples,  N.proj[,3,1,1,s], phiA.proj[,3,1]*(1-epsA[,2]))
    #new movers - intermediate class - last period's 30-mo+ old residents survive and start moving but stay in state AND last period's 30-mo+ old movers continue moving but stay in state 
    #all 1 here bc same year
    N.movers.newmove.proj[,3,2,1,s] <- rbinom(nSamples, N.proj[,3,1,1,s], phiA.proj[,3,1]*epsA[,2]*alpha) 
    N.movers.oldmove.proj[,3,2,1,s] <- rbinom(nSamples, N.movers.proj[,3,1,1,s], phiB.proj[,3,1]*epsB[,2]*alpha)
    N.movers.proj[,3,2,1,s] <- N.movers.newmove.proj[,3,2,1,s] + N.movers.oldmove.proj[,3,2,1,s]
    #settlers - intermediate class - last period's 30-mo+ old movers settle at s  
    N.settlers.proj[,3,2,1,s] <- rbinom(nSamples, N.movers.proj[,3,1,1,s], phiB.proj[,3,1]*(1-epsB[,2]))
    
    #close s loop
  }  
  
  #----------------------------- 
  
  ##### FIRST MOVEMENT FUNCTION GOES HERE -----##### 
  
  n.settlers.for.fxn <- array(NA,dim = c(nSamples,2,224))
  n.settlers.for.fxn <- N.settlers.proj[,c(2:3),2,1,] #just getting nSamples x 2 x site
  
  n.res <- array(NA,dim = c(nSamples,224))
  n.res <- N.stayers.proj[,1,2,1,] + N.stayers.proj[,2,2,1,] + N.stayers.proj[,3,2,1,]
  
  new.guys <- get.move(n.settlers.for.fxn,n.res,site_check,array_probs,array_siteID)  
  
  for(i in 1:nSamples){ #loop over nSamples to see which territories are occupied 
    
    #which ids are occupied?
    immig_id <- which(N.stayers.proj[i,1,2,1,] + N.stayers.proj[i,2,2,1,] + N.stayers.proj[i,3,2,1,]+
                        new.guys[[1]][i,] + new.guys[[2]][i,] >0)
    #keeps total number of immigrants entering each year to the asymptote from the growth model (ie, limits immigration so it doesn't grow with increasing # of packs)
    lambda.immig.t <- lambda.immig[i]*(assmp.immig/length(immig_id))
    
    for(s in immig_id){
      
      Tot.immig.proj[i,2,1,s] <- rpois(1, lambda.immig.t) #no .proj bc taken from data model
      #there are no immigrant 6-11.99 mo olds
      N.immig.proj[i,1,2,1,s] <- 0
      #12-23.99 mo old class is the first class that can immigrate
      N.immig.proj[i,2,2,1,s] <- rbinom(1, Tot.immig.proj[i,2,1,s], probImmig[1])
      # group G: deterministic
      N.immig.proj[i,3,2,1,s] <- Tot.immig.proj[i,2,1,s] - N.immig.proj[i,2,2,1,s]
    }}
  
  N.proj[,1,2,1,] <- N.stayers.proj[,1,2,1,]
  N.proj[,2,2,1,] <- N.stayers.proj[,2,2,1,] + N.immig.proj[,2,2,1,] + new.guys[[1]] #these have rejected settlers and new guys
  N.proj[,3,2,1,] <- N.stayers.proj[,3,2,1,] + N.immig.proj[,3,2,1,] + new.guys[[2]]
  
  newguys[,2,1,] <- new.guys[[1]] + new.guys[[2]] #these are new guys only
  
  ##ATTRACTION FUNCTION HERE
  
  n.wolves.solo.fxn <- array(NA,dim = c(nSamples,3,224))
  
  n.wolves.solo.fxn <- N.proj[,,2,1,] #just getting nSamples x 3 x site
  
  #solo function
  group.neighbors <- get.solos(n.wolves.solo.fxn, neighbor_list)
  
  N.proj[,,2,1,] <- group.neighbors
  
  ###### MOVING AHEAD TO T==2 ######
  
  ##### POPULATION PROJECTION MODEL #####
  
  for (t in 1:(proj-1)){ #this is the big outer t loop
    
    for (s in 1:S){ #running through all 224 territories
      
      #----------------------------- 
      #Dec 18 mo 
      
      #last period's 12-mo olds survive and don't start moving
      N.stayers.proj[,2,1,t+1,s] <- rbinom(nSamples, N.proj[,1,2,t,s], phiA.proj[,2,2*t]*(1-epsA[,1]))
      
      #last periods 12-mo olds survive, initiate movement, but stay in state
      #new lines June 2022
      N.movers.newmove.proj[,2,1,t+1,s] <- rbinom(nSamples, N.proj[,1,2,t,s], phiA.proj[,2,2*t]*epsA[,1]*alpha ) #formerly sum(N.proj[,2,2,t,]) + sum(N.proj[,3,2,t,])
      N.movers.oldmove.proj[,2,1,t+1,s] <- rbinom(nSamples, N.movers.proj[,1,2,t,s], phiB.proj[,2,2*t]*epsB[,1]*alpha )
      N.movers.proj[,2,1,t+1,s] <- N.movers.newmove.proj[,2,1,t+1,s] + N.movers.oldmove.proj[,2,1,t+1,s]
      
      #can also have settlers at 18 mo
      N.settlers.proj[,2,1,t+1,s] <- rbinom(nSamples, N.movers.proj[,1,2,t,s], phiB.proj[,2,2*t]*(1-epsB[,1]))
      
      #-----------------------------
      
      #Dec 30 mo+ (i.e., 30 mo, 42 mo, 54 mo, 66 mo, 78 mo, 90 mo...)
      #key here is that this group is 30 PLUS months; has 30, 42, 54 mos
      
      #stayers - intermediate class - last period's 24-mo old residents and 36-mo+ old residents survive and don't initiate movement 
      N.stayers.proj[,3,1,t+1,s] <- rbinom(nSamples, N.proj[,2,2,t,s] + N.proj[,3,2,t,s], 
                                           phiA.proj[,3,2*t]*(1-epsA[,2])) 
      
      #new and old movers - intermediate class - last period's 24-mo old and 36-mo+ old residents survive and start moving but stay in state AND last period's 24-mo old and 36-mo+ old movers continue moving but stay in state
      N.movers.newmove.proj[,3,1,t+1,s] <- rbinom(nSamples, N.proj[,2,2,t,s] + N.proj[,3,2,t,s], phiA.proj[,3,2*t]*epsA[,2]*alpha ) 
      N.movers.oldmove.proj[,3,1,t+1,s] <- rbinom(nSamples, N.movers.proj[,2,2,t,s]+ N.movers.proj[,3,2,t,s], phiB.proj[,3,2*t]*epsB[,2]*alpha )
      N.movers.proj[,3,1,t+1,s] <- N.movers.newmove.proj[,3,1,t+1,s] + N.movers.oldmove.proj[,3,1,t+1,s]
      
      #settlers - intermediate class - last periods 24-mo old movers and 36-mo+ old movers settle at s  
      N.settlers.proj[,3,1,t+1,s] <- rbinom(nSamples, N.movers.proj[,2,2,t,s]+N.movers.proj[,3,2,t,s], phiB.proj[,3,2*t]*(1-epsB[,2]))
      
    } #close s loop
    
    #Dec 6 mo olds
    for(i in 1:nSamples){
      for (s in 1:S){ #start s loop again
        if (N.stayers.proj[i,3,1,t+1,s] >= 2){ #ok to be N.proj bc no breeding w solo indivs anyway
          lambda.pups.proj[i,t+1,s] <- rcat(1,probs.pup[i,])-1 #need to subtract 1 to make it btw 0 and 6 pups
        }
        else
        {lambda.pups.proj[i,t+1,s] <- 0}
      }}
    
    for (s in 1:S){ #assign 6-mo olds in Dec of that year
      N.proj[,1,1,t+1,s] <- lambda.pups.proj[,t+1,s]
    }
    
    ##### SECOND MOVEMENT FUNCTION GOES HERE -----##### 
    
    #added third dimension for 18 mo olds
    n.settlers.for.fxn <- array(NA,dim = c(nSamples,2,224))
    
    #now we add 18-mo settlers (Jun 2022)
    n.settlers.for.fxn <- N.settlers.proj[,c(2:3),1,t+1,] #just getting nSamples x 3 x site
    
    n.res <- array(NA,dim = c(nSamples,224))
    n.res <- N.proj[,1,1,t+1,] + N.stayers.proj[,2,1,t+1,] + N.stayers.proj[,3,1,t+1,]
    
    #call function
    new.guys <- get.move(n.settlers.for.fxn,n.res,site_check,array_probs,array_siteID)  
    
    ##### WE CAN ADD IMMIGRANTS HERE FOR DECEMBER
    
    for(i in 1:nSamples){
      #which ids are occupied?
      immig_id <- which(N.proj[i,1,1,t+1,] + N.stayers.proj[i,2,1,t+1,] + N.stayers.proj[i,3,1,t+1,] +
                          new.guys[[1]][i,] + new.guys[[2]][i,] >0)
      
      #keeps total number of immigrants entering each year to the asymptote from the growth model (ie, limits immigration so it doesn't grow with increasing # of packs)
      lambda.immig.t <- lambda.immig[i]*(assmp.immig/length(immig_id))
      
      for(s in immig_id){
        Tot.immig.proj[i,1,t+1,s] <- rpois(1, lambda.immig.t) #no .proj bc taken from data model
        #there are no immigrant 6-11.99 mo olds
        N.immig.proj[i,1,1,t+1,s] <- 0
        #12-23.99 mo old class is the first class that can immigrate
        N.immig.proj[i,2,1,t+1,s] <- rbinom(1, Tot.immig.proj[i,1,t+1,s], probImmig[1])
        # group G: deterministic
        N.immig.proj[i,3,1,t+1,s] <- Tot.immig.proj[i,1,t+1,s] - N.immig.proj[i,2,1,t+1,s]
      }}
    
    N.proj[,2,1,t+1,] <- N.stayers.proj[,2,1,t+1,] + N.immig.proj[,2,1,t+1,] + new.guys[[1]] #these have rejected settlers and new guys
    N.proj[,3,1,t+1,] <- N.stayers.proj[,3,1,t+1,] + N.immig.proj[,3,1,t+1,] + new.guys[[2]]
    
    newguys[,1,t+1,] <- new.guys[[1]] + new.guys[[2]] #new guys only
    
    ##### REMOVAL FUNCTION GOES HERE -----##### 
    
    #THIS IS WHERE REMOVALS HAPPEN; HAPPEN ANNUALLY IN TIME PERIOD 1 (DECEMBER)
    
    n.wolves.EWash.fxn <- array(NA,dim = c(nSamples,3,length(EWash)))
    
    #N.proj numbers should be going into the removal function because only sites with 2+ adults can get removed anyway
    n.wolves.EWash.fxn <- N.proj[,,1,t+1,EWash] #just getting nSamples x 3 x site
    
    #call function
    n.postremove.EWash <- get.removals(n.wolves.EWash.fxn, removal_rate)
    
    N.proj[,,1,t+1,EWash] <- n.postremove.EWash
    
    ##### TRANSLOCATION FUNCTION GOES HERE -----##### 
    
    #adjust t to whenever translocation will occur
    
    if(analysis=="translocation" && t==7){
      
      n.wolves.transl.fxn <- array(NA,dim = c(nSamples,3,224))
      n.wolves.transl.fxn <- N.proj[,,1,t+1,] #just getting nSamples x 3 x site
      
      #call function
      n.post_translocation <- get.translocations(n.wolves.transl.fxn, EWash, site)
      
      N.proj[,1,1,t+1,] <- N.proj[,1,1,t+1,] + n.post_translocation[[1]]
      N.proj[,3,1,t+1,] <- N.proj[,3,1,t+1,] + n.post_translocation[[2]]
      
    }
    
    ##ATTRACTION FUNCTION HERE
    n.wolves.solo.fxn <- array(NA,dim = c(nSamples,3,224))
    
    n.wolves.solo.fxn <- N.proj[,,1,t+1,] #just getting nSamples x 3 x site
    
    #solo function
    group.neighbors <- get.solos(n.wolves.solo.fxn, neighbor_list)
    
    N.proj[,,1,t+1,] <- group.neighbors
    
    Ntot.proj[,t+1,] <-
      N.proj[,1,1,t+1,] + N.proj[,2,1,t+1,] + N.proj[,3,1,t+1,]
    
    for (s in 1:S){ #start s loop again
      
      #----------------------------- 
      #Jun 12 mo 
      
      #last period's 6-mo olds survive (added epsA Jun 2022)
      N.stayers.proj[,1,2,t+1,s] <- rbinom(nSamples, N.proj[,1,1,t+1,s], phiA.proj[,1,(2*t+1)]*(1-epsA[,1]))
      
      #they can also move now (new Jun 2022)
      N.movers.proj[,1,2,t+1,s] <- rbinom(nSamples, N.proj[,1,1,t+1,s], phiA.proj[,1,(2*t+1)]*epsA[,1]*alpha) 
      
      #----------------------------- 
      
      #Jun 24 mo 
      
      #stayers - intermediate class - last period's 18-mo old residents survive and don't initiate movement  
      N.stayers.proj[,2,2,t+1,s] <- rbinom(nSamples, N.proj[,2,1,t+1,s], phiA.proj[,2,(2*t+1)]*(1-epsA[,1]))
      
      #new and old movers - intermediate class - last period's 18-mo old residents survive and start moving but stay in state AND last period's 18-mo old movers continue moving but stay in state 
      #all are t+1 here because from same year
      
      N.movers.newmove.proj[,2,2,t+1,s] <- rbinom(nSamples, N.proj[,2,1,t+1,s], phiA.proj[,2,(2*t+1)]*epsA[,1]*alpha) #formerly sum(N.proj[,2,1,t+1,])
      N.movers.oldmove.proj[,2,2,t+1,s] <- rbinom(nSamples, N.movers.proj[,2,1,t+1,s], phiB.proj[,2,(2*t+1)]*epsB[,1]*alpha) 
      N.movers.proj[,2,2,t+1,s] <- N.movers.newmove.proj[,2,2,t+1,s] + N.movers.oldmove.proj[,2,2,t+1,s]
      
      #here are our FIRST settlers - intermediate class - last periods 18-mo old new movers survive, stop moving, and settle at s  
      N.settlers.proj[,2,2,t+1,s] <- rbinom(nSamples, N.movers.proj[,2,1,t+1,s], phiB.proj[,2,(2*t+1)]*(1-epsB[,1]))
      
      #----------------------------- 
      
      #Jun 36 mo+ (i.e., 36 mo, 48 mo, 60 mo, 72 mo, 84 mo, 96 mo...) 
      
      #stayers - intermediate class - last period's 30-mo+ old residents survive and don't initiate movement  
      N.stayers.proj[,3,2,t+1,s] <- rbinom(nSamples,  N.proj[,3,1,t+1,s], phiA.proj[,3,(2*t+1)]*(1-epsA[,2]))
      
      #new movers - intermediate class - last period's 30-mo+ old residents survive and start moving but stay in state AND last period's 30-mo+ old movers continue moving but stay in state 
      #all t+1 here bc same year
      N.movers.newmove.proj[,3,2,t+1,s] <- rbinom(nSamples, N.proj[,3,1,t+1,s], phiA.proj[,3,(2*t+1)]*epsA[,2]*alpha) #formerly sum(N.proj[,3,1,t,])
      N.movers.oldmove.proj[,3,2,t+1,s] <- rbinom(nSamples, N.movers.proj[,3,1,t+1,s], phiB.proj[,3,(2*t+1)]*epsB[,2]*alpha)
      N.movers.proj[,3,2,t+1,s] <- N.movers.newmove.proj[,3,2,t+1,s] + N.movers.oldmove.proj[,3,2,t+1,s]
      
      #settlers - intermediate class - last period's 30-mo+ old movers settle at s  
      N.settlers.proj[,3,2,t+1,s] <- rbinom(nSamples, N.movers.proj[,3,1,t+1,s], phiB.proj[,3,(2*t+1)]*(1-epsB[,2]))
      
      #----------------------------- 
    } #close s loop
    
    ##### THIRD MOVEMENT FUNCTION GOES HERE -----##### 
    
    dim(N.settlers.proj)
    n.settlers.for.fxn <- array(0,dim = c(nSamples,2,224))
    n.settlers.for.fxn <- N.settlers.proj[,c(2:3),2,t+1,] #just getting nSamples x 2 x site
    
    n.res <- array(NA,dim = c(nSamples,224))
    n.res <- N.stayers.proj[,1,2,t+1,] + N.stayers.proj[,2,2,t+1,] + N.stayers.proj[,3,2,t+1,]
    
    new.guys <- get.move(n.settlers.for.fxn,n.res,site_check,array_probs,array_siteID)  
    
    ##### WE CAN ADD IMMIGRANTS HERE FOR JUNE
    
    for(i in 1:nSamples){
      #which ids are occupied?
      immig_id <- which(N.stayers.proj[i,1,2,t+1,] + N.stayers.proj[i,2,2,t+1,] + N.stayers.proj[i,3,2,t+1,]+
                          new.guys[[1]][i,] + new.guys[[2]][i,] >0)
      
      #keeps total number of immigrants entering each year to the asymptote from the growth model (ie, limits immigration so it doesn't grow with increasing # of packs)
      lambda.immig.t <- lambda.immig[i]*(assmp.immig/length(immig_id))
      
      for(s in immig_id){
        Tot.immig.proj[i,2,t+1,s] <- rpois(1, lambda.immig.t) #no .proj bc taken from data model
        #there are no immigrant 6-11.99 mo olds
        N.immig.proj[i,1,2,t+1,s] <- 0
        #12-23.99 mo old class is the first class that can immigrate
        N.immig.proj[i,2,2,t+1,s] <- rbinom(1, Tot.immig.proj[i,2,t+1,s], probImmig[1])
        # group G: deterministic
        N.immig.proj[i,3,2,t+1,s] <- Tot.immig.proj[i,2,t+1,s] - N.immig.proj[i,2,2,t+1,s]
      }}
    
    N.proj[,1,2,t+1,] <- N.stayers.proj[,1,2,t+1,]
    N.proj[,2,2,t+1,] <- N.stayers.proj[,2,2,t+1,] + N.immig.proj[,2,2,t+1,] + new.guys[[1]] #these have new guys and rejected settlers
    N.proj[,3,2,t+1,] <- N.stayers.proj[,3,2,t+1,] + N.immig.proj[,3,2,t+1,] + new.guys[[2]]
    newguys[,2,t+1,] <- new.guys[[1]] + new.guys[[2]] #new guys only
    #we don't do Ntot here bc we only do that for first period
    
    ##ATTRACTION FUNCTION HERE
    n.wolves.solo.fxn <- array(NA,dim = c(nSamples,3,224))
    
    n.wolves.solo.fxn <- N.proj[,,2,t+1,] #just getting nSamples x 3 x site
    
    #solo function
    group.neighbors <- get.solos(n.wolves.solo.fxn, neighbor_list)
    
    N.proj[,,2,t+1,] <- group.neighbors
    
  } #close big t loop
  
  #Ntot
  for(i in 1:nSamples){
    for(t in 1:proj){
      #all of these are counting packs where n > 2 per site
      Nglobal_state.proj[i,t] <- sum(Ntot.proj[i,t,])
      Nglobal_state_wmove.proj[i,t] <- sum(Ntot.proj[i,t,]) + sum(N.movers.proj[i,,1,t,])
      NAdult_state.proj[i,t] <- sum(N.proj[i,2,1,t,]) + sum(N.proj[i,3,1,t,])
      NAdult_EWash.proj[i,t] <- sum(N.proj[i,2,1,t,EWash]) + sum(N.proj[i,3,1,t,EWash])
      NAdult_NCasc.proj[i,t] <- sum(N.proj[i,2,1,t,NorthCasc]) + sum(N.proj[i,3,1,t,NorthCasc])
      NAdult_SCasc.proj[i,t] <- sum(N.proj[i,2,1,t,SouthCasc]) + sum(N.proj[i,3,1,t,SouthCasc])
      NSite_state.proj[i,t] <- length(which((N.proj[i,2,1,t,] + N.proj[i,3,1,t,]>=2) & N.proj[i,1,1,t,]>=2))
      NSite_EWash.proj[i,t] <- length(which((N.proj[i,2,1,t,EWash] + N.proj[i,3,1,t,EWash]>=2) & N.proj[i,1,1,t,EWash]>=2))
      NSite_NCasc.proj[i,t] <- length(which((N.proj[i,2,1,t,NorthCasc] + N.proj[i,3,1,t,NorthCasc]>=2) & N.proj[i,1,1,t,NorthCasc]>=2))
      NSite_SCasc.proj[i,t] <- length(which((N.proj[i,2,1,t,SouthCasc] + N.proj[i,3,1,t,SouthCasc]>=2) & N.proj[i,1,1,t,SouthCasc]>=2))
      for(s in 1:S){
        N_newguys.proj[i,t,s] <- sum(newguys[i,,t,s])
        BP_presence.proj[i,t,s] <- ifelse(N.proj[i,2,1,t,s] + N.proj[i,3,1,t,s]>=2 & N.proj[i,1,1,t,s]>=2,1,0)
        Two_Adult.proj[i,t,s] <- ifelse(N.proj[i,2,1,t,s] + N.proj[i,3,1,t,s]>=2,1,0)
        Pack_Size.proj[i,t,s] <- N.proj[i,1,1,t,s] + N.proj[i,2,1,t,s] + N.proj[i,3,1,t,s]
      }}}
  
  #growth rate over the whole study period
  lambda.proj <- matrix(NA, nrow=nSamples, ncol=proj-1)  
  #need to replace Inf with NA in Nglobal_state.proj
  for (t in 2:proj) {
    # mean and quantiles per year across mcmc samples; leave na.rm for zero size pops in mcmc samples
    lambda.proj[,t-1] <- Nglobal_state.proj[,t]/Nglobal_state.proj[,t-1] 
    # we need the Infs to become NAs
    lambda.proj[,t-1][is.infinite(lambda.proj[,t-1])] <- NA                   
    lambda.proj[,t-1][is.nan(lambda.proj[,t-1])] <- NA                   
  } #closes t on lambda
  
  
  #### derive and store values for each simulation
  Lambda.mean[1:nSamples,,sim] <- as.matrix(lambda.proj)
  Nglobal_state.mean[1:nSamples,,sim] <- as.matrix(Nglobal_state.proj)
  Nglobal_state_wmove.mean[1:nSamples,,sim] <- as.matrix(Nglobal_state_wmove.proj)
  NAdult_state.mean[1:nSamples,,sim] <- as.matrix(NAdult_state.proj)
  NAdult_EWash.mean[1:nSamples,,sim] <- as.matrix(NAdult_EWash.proj)
  NAdult_NCasc.mean[1:nSamples,,sim] <- as.matrix(NAdult_NCasc.proj)
  NAdult_SCasc.mean[1:nSamples,,sim] <- as.matrix(NAdult_SCasc.proj)
  NSite_state.mean[1:nSamples,,sim] <- as.matrix(NSite_state.proj)
  NSite_EWash.mean[1:nSamples,,sim] <- as.matrix(NSite_EWash.proj)
  NSite_NCasc.mean[1:nSamples,,sim] <- as.matrix(NSite_NCasc.proj)
  NSite_SCasc.mean[1:nSamples,,sim] <- as.matrix(NSite_SCasc.proj)
  Newguys.mean[,,,sim] <- as.array(N_newguys.proj)
  Ntot.site[,,,sim] <- as.array(Ntot.proj)
  BP_Presence[,,,sim] <- as.array(BP_presence.proj)
  Two_Adult[,,,sim] <- as.array(Two_Adult.proj)
  Pack_Size[,,,sim] <- as.array(Pack_Size.proj)
  
} #close sim



dim(BP_Presence)
#this will give max pack size across x samples
Pack_Size_max <- apply(Pack_Size,c(1),max)
#this will get probability of having BP by site and year
BP_Presence_summary <- apply(BP_Presence,c(2,3),mean)
Two_Adult_summary <- apply(Two_Adult,c(2,3),mean)
#this will get mean and median wolves by site and year, and mean new guys
Ntot.site_mean <- apply(Ntot.site,c(2,3),mean)
Ntot.site_median <- apply(Ntot.site,c(2,3),mean)
Newguys.mean <- apply(Newguys.mean,c(2,3),mean)

save(Lambda.mean,
     Ntot.site_mean, Ntot.site_median, Newguys.mean,
     BP_Presence_summary, BP_Presence, Pack_Size_max,Two_Adult_summary,Two_Adult,
     Nglobal_state.mean, Nglobal_state_wmove.mean,
     NAdult_state.mean,
     NAdult_EWash.mean, NAdult_NCasc.mean, NAdult_SCasc.mean, Newguys.mean,
     NSite_state.mean, NSite_EWash.mean, NSite_NCasc.mean, NSite_SCasc.mean, file="10_Disease_25Perc_Projection.RData")