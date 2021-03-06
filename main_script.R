#-------------------------------PRELIMINARIES--------------------------------------
forgetting <- 2     # 1: use constant factor 2: use variable factor
lambda <- 0.99      # Forgetting factor for the state equation variance
kappa <- 0.96       # Decay factor for measurement error variance
eta <- 0.99         # Forgetting factor for DPS (dynamic prior selection) and DMA

# Please choose:
p <- 1              # p is number of lags in the VAR part
nos <- 2            # number of subsets to consider (default is 3, i.e. 3, 7, and 25 variable VARs)
                    # if nos=1 you might want a single model. Which one is this?
single <- 1         # 1: 3 variable VAR
                    # 2: 7 variable VAR
                    # 3: 25 variable VAR
prior <- 1          # 1: Use Koop-type Minnesota prior
                    # 2: Use Litterman-type Minnesota prior
# Forecasting
first_sample_ends <- 1974.75 # The end date of the first sample in the 
# recursive exercise (default value: 1969:Q4)
# NO CHOICE OF FORECAST HORIZON, h=1 IN ALL INSTANCES OF THIS CODE

#----------------------------------LOAD DATA----------------------------------------
library(readr)
library(readxl)
DATA_GARY_large_VAR <- read_excel("C:/Users/Berna/Desktop/Projeto de Mestrado/Large-TVP-VAR/MATLAB functions/Data/DATA_GARY_large_VAR.xlsx", 
                                  skip = 4)
DATA_GARY_large_VAR <- as.matrix(DATA_GARY_large_VAR)
#View(DATA_GARY_large_VAR)

ydata <- read_delim("C:/Users/Berna/Desktop/Projeto de Mestrado/Large-TVP-VAR/MATLAB functions/Data/ydata.dat", 
                    "\t", escape_double = FALSE, 
                    col_names = FALSE, 
                    trim_ws = TRUE)
ydata <- as.matrix(ydata)
#View(ydata)

tcode <- read_csv("C:/Users/Berna/Desktop/Projeto de Mestrado/Large-TVP-VAR/MATLAB functions/Data/tcode.dat", 
                  col_names = FALSE)
tcode <- as.vector(tcode)
#View(tcode)

ynames <- read_excel("C:/Users/Berna/Desktop/Projeto de Mestrado/Large-TVP-VAR/MATLAB functions/Data/ynames.xlsx")
#View(ynames)

##
vars <- vector(mode = 'list', length = 6)
for (i in seq_along(vars)) {
    vars[[i]] <- read_excel("C:/Users/Berna/Desktop/Projeto de Mestrado/Large-TVP-VAR/MATLAB functions/Data/vars.xlsx", 
                    sheet = i, col_names = FALSE)
}
#str(vars)

#  ------------------------------------------------------------------------

# Create dates variable
start_date <- 1959.00  # 1959.Q1
end_date   <- 2010.25  # 2010.Q2
yearlab    <- seq(from = 1959, to = 2010.25, by = 0.25)
T_thres    <- which(yearlab == first_sample_ends) # find tau_0 (first sample)

# Transform data to stationarity
# Y: standard transformations (for iterated forecasts, and RHS of direct forecasts)
Y <- transform(ydata, tcode, yearlab)[[1]]
yearlab <- transform(ydata, tcode, yearlab)[[2]]

# Select a subset of the data to be used for the VAR
if (nos > 3) {
    stop('DMA over too many models, memory concerns...')
}

Y1 <- vector(mode = 'list', length = nos)
Ytemp <- standardize1(Y, T_thres)
M <- vector(mode = 'list', length = nos)
for (ss in seq(nos)) {
    if (nos != 1) {
        single <- ss
    }
    select_subset <- vars[[ss]]
    Y1[[ss]] <- Ytemp[ , unlist(select_subset)] 
    M[[ss]] <- max(nrow(select_subset), ncol(select_subset)) # M is the dimensionality of Y
}
t <- nrow(Y1[[1]])

# The first nfocus variables are the variables of interest for forecasting
nfocus <- 3

# ===================================| VAR EQUATION |==============================
# Generate lagged Y matrix. This will be part of the X matrix
x_t <- vector(mode = 'list', length = nos)
x_f <- vector(mode = 'list', length = nos)
y_t <- vector(mode = 'list', length = nos)
K   <- vector(mode = 'list', length = nos)
for (ss in seq(nos)) { #ss=1:nos
    ylag <- mlag2(Y1[[ss]], p)
    ylag <- ylag[(p + 1):nrow(ylag), , drop = FALSE]
    temp <- create_RHS(ylag, M[[ss]], p, t)[['x_t']]
    kk   <- create_RHS(ylag, M[[ss]], p, t)[['K']]
    x_t[[ss]] <- temp
    K[[ss]]   <- kk
    x_f[[ss]] <- ylag
    y_t[[ss]] <- Y1[[ss]][(p + 1):nrow(Y1[[ss]]), ] # check this lines later for p!=2. 
}

yearlab <- yearlab[-c(1:p)] # and this too!
# Time series observations
t <- nrow(y_t[[1]]) 

#----------------------------PRELIMINARIES---------------------------------
#========= PRIORS:
# Set the alpha_bar and the set of gamma values
alpha_bar <- 10
gamma <- c(1e-10, 1e-5, 0.001, 0.005, 0.01, 0.05, 0.1)
nom <- length(gamma)  # This variable defines the number of DPS models

#-------- Now set prior means and variances (_prmean / _prvar)
theta_0_prmean <- vector('list', length = nos)
theta_0_prvar <-  vector('list', length = nos)
Sigma_0 <- vector('list', length = nos)
for (list in seq_along(theta_0_prmean)) {
    theta_0_prmean[[list]] <- matrix(data = NA, nrow = K[[list]], ncol = nom)
}
for (list in seq_along(theta_0_prvar)) {
    theta_0_prvar[[list]] <- array(data = NA, dim = c(K[[list]], K[[list]], nom))
}
for (ss in seq(nos)) {
    if (prior == 1) {            # 1) "No dependence" prior
        for (i in seq(nom)) {       
            prior_out  <- Minn_prior_KOOP(alpha_bar, gamma[i], M[[ss]], p, K[[ss]])
            theta_0_prmean[[ss]][ , i]  <- prior_out$a_prior
            theta_0_prvar[[ss]][ , , i] <- prior_out$V_prior
        }
        Sigma_0[[ss]] <- cov(y_t[[ss]][seq(T_thres), ])  # Initialize the measurement covariance matrix (Important!)
    } else if (prior == 2) {     # 2) Full Minnesota prior
        for (i in seq(nom)) {
            prior_out <-  Minn_prior_LITT(y_t[[ss]][1:T_thres, ],
                                          x_f[[ss]][1:T_thres, ],
                                          alpha_bar,
                                          gamma[i],
                                          M[[ss]],
                                          p,
                                          K[[ss]],
                                          T_thres)
            # sigma_var  <- prior_out[['Sigma_0']]   
            theta_0_prmean[[ss]][ , i]  <- prior_out$prior_mean
            theta_0_prvar[[ss]][ , , i] <- prior_out$prior_var
        }
        #Sigma_0{ss,1} = sigma_var; # Initialize the measurement covariance matrix (Important!)
        Sigma_0[[ss]] <- cov(y_t[[ss]][seq(T_thres), ])
    }
}

# Define forgetting factor lambda:
lambda_t <- vector('list', length = nos)
for (ss in seq(nos)) {
    if (forgetting == 1) {
        # CASE 1: Choose the forgetting factor   
        inv_lambda <- 1 / lambda
        lambda_t[[ss]] <- lambda * matrix(data = 1, nrow = t, ncol = nom) 
    } else if (forgetting == 2) {
        # CASE 2: Use a variable (estimated) forgetting factor
        lambda_min <- 0.97
        inv_lambda <- 1 / 0.99
        alpha <- 1
        LL <- 1.1
        lambda_t[[ss]] <- matrix(data = 0, nrow = t, ncol = nom)
    } else {
        stop('Wrong specification of forgetting procedure')
    }
}

# Initialize matrices
sum_prob_omega <- vector(mode = 'list', length = nos)

theta_pred <- vector(mode = 'list', length = nos) 
for (list in seq_along(theta_pred)) { 
    theta_pred[[list]] <- array(data = NA, dim = c(K[[list]], t, nom)) 
}

theta_update <- vector(mode = 'list', length = nos)
for (list in seq_along(theta_update)) { 
    theta_update[[list]] <- array(data = NA, dim = c(K[[list]], t, nom)) 
}

R_t <- vector(mode = 'list', length = nos)
for (list in seq_along(R_t)) { 
    R_t[[list]] <- array(data = NA, dim = c(K[[list]], K[[list]], nom)) 
}

S_t <- vector(mode = 'list', length = nos)
for (list in seq_along(S_t)) { 
    S_t[[list]] <- array(data = NA, dim = c(K[[list]], K[[list]], nom)) 
}

y_t_pred <- vector(mode = 'list', length = nos)
for (list in seq_along(y_t_pred)) { 
    y_t_pred[[list]] <- array(data = NA, dim = c(M[[list]], t, nom)) 
}

e_t <- vector(mode = 'list', length = nos)
for (list in seq_along(e_t)) { 
    e_t[[list]] <- array(data = NA, dim = c(M[[list]], t, nom)) 
}

A_t <- vector(mode = 'list', length = nos) # this is different from the matlab code. Koop's uses just one matrix for  
for (list in seq_along(A_t)) {             # all VAR dimmensions and I am using one list for each dimmension.
    A_t[[list]] <- matrix(data = NA, nrow = M[[list]], ncol = M[[list]])
}

V_t <- vector(mode = 'list', length = nos)
for (list in seq_along(V_t)) { 
    V_t[[list]] <- array(data = NA, dim = c(M[[list]], M[[list]], t, nom))  
}

y_fore <- vector(mode = 'list', length = nos)
for (list in seq_along(y_fore)) { 
    y_fore[[list]] <- array(data = NA, dim = c(1, M[[list]], nom, 2000)) # why 2000?  
}

omega_update  <- vector(mode = 'list', length = nos)
for (list in seq_along(omega_update)) { 
    omega_update[[list]] <- matrix(data = NA, nrow = t, ncol = nom) 
}

omega_predict <- vector(mode = 'list', length = nos)
for (list in seq_along(omega_predict)) { 
    omega_predict[[list]] <- matrix(data = NA, nrow = t, ncol = nom) 
}

Yraw_f <- vector(mode = 'list', length = nos)
for (list in seq_along(Yraw_f)) { 
    Yraw_f[[list]] <- matrix(data = NA, nrow = 1, ncol = M[[list]]) 
}

ksi_update  <- matrix(data = 0, nrow = t, ncol = nos)
ksi_predict <- matrix(data = 0, nrow = t, ncol = nos)
w_t         <- vector(mode = 'list', length = nos) 
for (list in seq_along(w_t)) { 
    w_t[[list]] <- array(data = NA, dim = c(1, t, nom)) 
}

w2_t          <- matrix(data = 0, nrow = t, ncol = nos)
f_l           <- matrix(data = 0, nrow = nom, ncol = 1)
max_prob_DMS  <- matrix(data = 0, nrow = t, ncol = 1)
index_best    <- matrix(data = 0, nrow = t, ncol = 1)
index_DMA     <- matrix(data = 0, nrow = t, ncol = nos)

anumber <- t - T_thres + 1
nfore <- 1

y_t_DMA    <- array(data = 0, dim = c(nfore, nfocus, anumber))
y_t_DMS    <- array(data = 0, dim = c(nfore, nfocus, anumber))
LOG_PL_DMA <- array(data = 0, dim = c(anumber, nfore))
MSFE_DMA   <- array(data = 0, dim = c(anumber, nfocus, nfore))
MAFE_DMA   <- array(data = 0, dim = c(anumber, nfocus, nfore))
LOG_PL_DMS <- array(data = 0, dim = c(anumber, nfore))
MSFE_DMS   <- array(data = 0, dim = c(anumber, nfocus, nfore))
MAFE_DMS   <- array(data = 0, dim = c(anumber, nfocus, nfore))
logpl_DMA  <- array(data = 0, dim = c(anumber, nfocus, nfore))
logpl_DMS  <- array(data = 0, dim = c(anumber, nfocus, nfore))
offset     <- 1e-8  # just a constant for numerical stability

#----------------------------- END OF PRELIMINARIES ---------------------------
aux1 <- vector(mode = 'list', length = nos)
for (list in seq_along(aux1)) {
    aux1[[list]] <- matrix(data = rnorm(M[[list]] * 2000), nrow = M[[list]], ncol = 2000)
}

max_prob <- vector(mode = 'list', length = nos)
k_max <- vector(mode = 'list', length = nos)

Minn_gamms <- vector(mode = 'list', length = nos)
for (list in seq_along(Minn_gamms)) {
    Minn_gamms[[list]] <- matrix(data = NA, nrow = t - T_thres + 1, ncol = 1)
}

bbtemp <- vector(mode = 'list', length = nos)
for (list in seq_along(bbtemp)) {
    bbtemp[[list]] <- matrix(data = 0, nrow = (M[[list]] * M[[list]]) * 2, ncol = 1)
}

biga <- vector(mode = 'list', length = nos)
for (list in seq_along(biga)) {
    biga[[list]] <- matrix(data = 0, nrow = M[[list]], ncol = M[[list]] * p)
}


# ======================= BEGIN KALMAN FILTER ESTIMATION =======================

# create progress bar
pb <- txtProgressBar(min = 0, max = t, style = 3)

for (irep in seq(t)) {
    Sys.sleep(0.01)
    setTxtProgressBar(pb, irep)
    for (ss in seq(nos)) {  # LOOP FOR 1 TO NOS VAR MODELS OF DIFFERENT DIMENSIONS
        # Find sum of probabilities for DPS
        if (irep > 1) {
            sum_prob_omega[[ss]] <- sum((omega_update[[ss]][irep - 1, ]) ^ eta)  
            # this is the sum of the nom model probabilities (all in the power of the forgetting factor 'eta')
        }
        for (k in seq(nom)) { # LOOP FOR 1:NOM VAR MODELS WITH DIFFERENT DEGREES OF SHRINKAGE
            # Predict
            if (irep == 1) {
                theta_pred[[ss]][ , irep, k] <- theta_0_prmean[[ss]][ , k]         
                R_t[[ss]][ , , k] <- theta_0_prvar[[ss]][ , , k]           
                omega_predict[[ss]][irep, k] <- 1 / nom
            } else {
                theta_pred[[ss]][ , irep, k] <- theta_update[[ss]][ , irep - 1, k]
                R_t[[ss]][ , , k] <- (1 / lambda_t[[ss]][irep - 1, k]) * S_t[[ss]][ , , k]
                omega_predict[[ss]][irep, k] <- ((omega_update[[ss]][irep - 1, k]) ^ eta + offset) / (sum_prob_omega[[ss]] + offset)
            }
            xx <- x_t[[ss]][((irep - 1) * M[[ss]] + 1):(irep * M[[ss]]), ]
            y_t_pred[[ss]][ , irep, k] <- xx %*% theta_pred[[ss]][ , irep, k] # this is one step ahead prediction 

            # Prediction error. 
            e_t[[ss]][ , irep, k] <- t(y_t[[ss]][irep, ]) - y_t_pred[[ss]][ , irep, k] # This is one step ahead prediction error

            # Update forgetting factor
            if (forgetting == 2) {
                lambda_t[[ss]][irep, k] <- lambda_min + (1 - lambda_min) * (LL ^ (-round(alpha * t(e_t[[ss]][1:nfocus, irep, k]) %*% e_t[[ss]][1:nfocus, irep, k, drop = FALSE])))
            }
            
            # first update V[t], see the part below equation (10)
            A_t[[ss]] <- e_t[[ss]][ , irep, k] %*% t(e_t[[ss]][ , irep, k])
            if (irep == 1) {
                V_t[[ss]][ , , irep, k] <- kappa * Sigma_0[[ss]]
            } else {
                V_t[[ss]][ , , irep, k] <- kappa * squeeze(V_t[[ss]][ , , irep - 1, k]) + (1 - kappa) * A_t[[ss]]
            }
            #%         if all(eig(squeeze(V_t(:,:,irep,k))) < 0)
            #%             V_t(:,:,irep,k) = V_t(:,:,irep-1,k);       
            #%         end
            
            # update theta[t] and S[t]
            Rx <- R_t[[ss]][ , , k] %*% t(xx)
            KV <- squeeze(V_t[[ss]][ , , irep, k]) + xx %*% Rx 
            KG <- Rx %*% solve(KV)
            theta_update[[ss]][ , irep, k] <- theta_pred[[ss]][ , irep, k] + (KG %*% e_t[[ss]][ , irep, k])
            S_t[[ss]][ , , k] <- R_t[[ss]][ , ,k] - KG %*% (xx %*% R_t[[ss]][ , , k])
            
            # Find predictive likelihood based on Kalman filter and update DPS weights     
            if (irep == 1) {
                variance <- Sigma_0[[ss]][1:nfocus, 1:nfocus] + xx[1:nfocus, ] %*% Rx[ , 1:nfocus]
            } else {
                variance <- V_t[[ss]][1:nfocus, 1:nfocus, irep, k] + xx[1:nfocus, ] %*% Rx[ , 1:nfocus]
            }
            if (any(eigen(variance, only.values = TRUE)$values < 0)) {
                variance <- abs(diag(diag(variance)))
            }
            ymean <- y_t_pred[[ss]][1:nfocus, irep, k]
            ytemp <- t(y_t[[ss]][irep, 1:nfocus])
            f_l[k, 1] <- densidade(x = ytemp, mean = ymean, sigma = variance)
            w_t[[ss]][ , irep, k] <- omega_predict[[ss]][irep, k] %*% f_l[k, 1]
            
            # forecast simulation for h=1 only. Instead of saving only the mean and variance. 
            # I just generate 2000 samples from the predictive density
            variance2 <- V_t[[ss]][ , , irep, k] + xx %*% Rx
            if (any(eigen(variance2, only.values = TRUE)$values < 0)) { 
                variance2 <- abs(diag(diag(variance2)))
            }
            bbtemp[[ss]] <- as.matrix(theta_update[[ss]][(M[[ss]] + 1):K[[ss]], irep, k])  # get the draw of B(t) at time i=1,...,T  (exclude intercept)                   
            splace <- 0
            #biga <- 0
            for (ii in seq(p)) {
                for (iii in seq(M[[ss]])) {            
                    biga[[ss]][iii, ((ii - 1) * M[[ss]] + 1):(ii * M[[ss]])] <- t(bbtemp[[ss]][(splace + 1):(splace + M[[ss]]), ])
                    splace <- splace + M[[ss]]
                }
            }
            beta_fore <- rbind(t(theta_update[[ss]][1:M[[ss]], irep, k]), t(biga[[ss]]))
            if (p == 1) {
                ymean2 <- t(c(1, y_t[[ss]][irep, ]) %*% beta_fore) # x_f[[ss]][irep, 1:(M[[ss]] * (p - 1))
            } else {
                ymean2 <- t(c(1, y_t[[ss]][irep, ], x_f[[ss]][irep, 1:(M[[ss]] * (p - 1))]) %*% beta_fore)
            }
            y_fore[[ss]][1, , k, ] <- repmat(ymean2, 1, 2000) + t(chol(variance2)) %*% aux1[[ss]] 
        } # End cycling through nom models with different shrinkage factors
        
        # First calculate the denominator of Equation (19) (the sum of the w's)
        sum_w_t <- 0   
        for (k_2 in seq(nom)) {       
            sum_w_t <- sum_w_t + w_t[[ss]][ , irep, k_2] 
        }
        
        # Then calculate the DPS probabilities  
        for (k_3 in seq(nom)) {
            omega_update[[ss]][irep, k_3] <- (w_t[[ss]][ , irep, k_3] + offset) / (sum_w_t + offset)  # this is Equation (19)
        }
        max_prob[[ss]] <- max(omega_update[[ss]][irep, ])
        k_max[[ss]]    <- which.max(omega_update[[ss]][irep, ])
        index_DMA[irep, ss] <- k_max[[ss]]                              
        
        # Use predictive likelihood of best (DPS) model, and fight the weight for DMA     
        w2_t[irep, ss] <- omega_predict[[ss]][irep, k_max[[ss]]] %*% f_l[k_max[[ss]], 1]
        
        # Find "observed" out-of-sample data for MSFE and MAFE calculations
        if (irep <= (t - nfore)) {
            Yraw_f[[ss]] <- y_t[[ss]][(irep + 1):(irep + nfore), ] #Pseudo out-of-sample observations                   
        } else {
            Yraw_f[[ss]] <- y_t[[ss]][(irep + 1 - 1):t, ] # gambiarra.  
        }
    }
    
    # First calculate the denominator of Equation (19) (the sum of the w's)
    sum_w2_t <- 0   
    for (k_2 in seq(nos)) {       
        sum_w2_t <- sum_w2_t + w2_t[irep, k_2]
    }
    
    # Then calculate the DPS probabilities
    for (k_3 in seq(nos)) {
        ksi_update[irep, k_3] <- (w2_t[irep, k_3] + offset) / (sum_w2_t + offset)  # this is Equation (19)
    }
    
    # Find best model for DMS
    max_prob_DMS[irep, ] <- max(ksi_update[irep, ])
    ss_max <- which.max(ksi_update[irep, ]) 
    index_DMA[irep, 1] <- k_max[[ss_max]]
    
    # Now we cycled over NOM and NOS models, do DMA-over-DPS
    if (irep >= T_thres) {
        ii <- nfore
        weight_pred <- 0 * y_fore[[ss]][ii, 1:nfocus, k_max[[ss]], ]
        # DPS-DMA prediction
        for (ss in seq(nos)) {
            temp_predict <- y_fore[[ss]][ii, 1:nfocus, k_max[[ss]], ] * ksi_update[irep, ss]
            weight_pred  <- weight_pred + temp_predict
            Minn_gamms[[ss]][irep - T_thres + 1, 1] <- gamma[k_max[[ss]]]
        }

        y_t_DMA[ii, , irep - T_thres + 1] <- rowMeans(weight_pred)
        variance_DMA <- cov(t(squeeze(weight_pred)))

        y_t_DMS[ii, , irep - T_thres + 1] <- rowMeans(y_fore[[ss_max]][ii, 1:nfocus, k_max[[ss_max]], ])
        variance_DMS <- cov(t(squeeze(y_fore[[ss_max]][ii, 1:nfocus, k_max[[ss_max]], ])))


        LOG_PL_DMS[irep - T_thres + 1, ii] <- densidade(x     = t(Yraw_f[[ss]][1:nfocus]),
                                                        mean  = y_t_DMS[ii, , irep - T_thres + 1],
                                                        sigma = variance_DMS, 
                                                        log   = TRUE)
                                              + offset
        MAFE_DMS[irep - T_thres + 1, , ii] <- abs(Yraw_f[[ss]][1:nfocus] - squeeze(y_t_DMS[ii, , irep - T_thres + 1]))
        MSFE_DMS[irep - T_thres + 1, , ii] <- (Yraw_f[[ss]][1:nfocus] - squeeze(y_t_DMS[ii, , irep - T_thres + 1])) ^ 2


        LOG_PL_DMA[irep - T_thres + 1, ii] <- densidade(x     = t(Yraw_f[[ss]][1:nfocus]),
                                                        mean  = y_t_DMA[ii, , irep - T_thres + 1],
                                                        sigma = variance_DMA, 
                                                        log   = TRUE) 
                                              + offset
        MAFE_DMA[irep - T_thres + 1, , ii] <- abs(Yraw_f[[ss]][1:nfocus] - squeeze(y_t_DMA[ii, , irep - T_thres + 1]))
        MSFE_DMA[irep - T_thres + 1, , ii] <- (Yraw_f[[ss]][1:nfocus] - squeeze(y_t_DMA[ii, , irep - T_thres + 1])) ^ 2
        for (j in seq(nfocus)) {
            logpl_DMA[irep - T_thres + 1, j, ii] <- densidade(x     = t(Yraw_f[[ss]][j]),
                                                              mean  = y_t_DMA[ii, j, irep - T_thres + 1],
                                                              sigma = variance_DMA[j, j], 
                                                              log   = TRUE)
                                                    + offset
            logpl_DMS[irep - T_thres + 1, j, ii] <- densidade(x     = t(Yraw_f[[ss]][j]),
                                                              mean  = y_t_DMS[ii, j, irep - T_thres + 1],
                                                              sigma = variance_DMS[j, j], 
                                                              log   = TRUE)
                                                    + offset
        }
    }
}
#======================== END KALMAN FILTER ESTIMATION ========================

