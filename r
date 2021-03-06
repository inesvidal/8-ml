---
title: "Study on now well exercise is performed"
author: "Ines Vidal Castiñeira"
output: html_document
---
```{r init, cache=TRUE, echo=FALSE, warning=FALSE, results='hide', message=FALSE}
# To make code readable
library(knitr)
library(xtable)
library(markdown) 
library(rmarkdown) 
library(ggplot2) 
library(pander)
library(dplyr)
library(caret)
library(randomForest)
library(rpart)
library(rattle)
library(doMC)
registerDoMC(cores = 2)
library(YaleToolkit)
library(corrplot)
library(stats)
setwd("~/Coursera/8-ml/ml-project")
set.seed(12345)
#opts_chunk$set(echo = FALSE, cache = TRUE, fig.width=10, fig.height=6, fig.path='Figs/')#,warning=FALSE, message=FALSE, results='hide')
```

```{r, load-data, cache=TRUE, echo=FALSE}
url_train <- "https://d396qusza40orc.cloudfront.net/predmachlearn/pml-training.csv"
url_test <- "https://d396qusza40orc.cloudfront.net/predmachlearn/pml-testing.csv"

filename_train <- "pml-training.csv"
filename_test <- "pml-testing.csv"
if (!file.exists(filename_train)) {
    print("INFO: csv file not found")
    ### Getting the dataset, and unzipping the files
    download.file(url_train, filename_train, method = "curl", cacheOK = FALSE)
    date_downloaded <- date()
    }
if (!file.exists(filename_test)) {
    print("INFO: csv file not found")
    ### Getting the dataset, and unzipping the files
    download.file(url_test, filename_test, method = "curl")
    date_downloaded <- date()
    }

#opening the data
training <- read.csv(filename_train)
testing <- read.csv(filename_test)
```


## Data cleaning
First we review sparsity, and remove rows without any informed value and columns with over 95% uninformed values (they coincide with columns that are only recorded when variable *new_window*="yes"). 
###---> not so clear
Finally we exclude columns *row.names*, *X*, *user_name*, *raw_timestamp_part_1*, *raw_timestamp_part_2*, *cvtd_timestamp*, *new_window* and *num_window*, that are considered irrelevant to the experiment.

### <------- revisar el tema de complete.cases, para dejarlo por encima de un umbral y rellenar los otros

```{r, clean-data, cache=TRUE, echo=FALSE}
# Prediction study design
# predicting the classe of exercise being performed (classe column)

#whatis(training_cl1)
clean <- function(x){
    # Unify blanks and #DIV/0! into NA
    print("x0:")
    print(dim(x))

    x[x == "" | x == "#DIV/0!"] <- NA
    
    # remove variables/columns with over a certain % of NAs
    summary(colSums(is.na(x))/nrow(x)) # only a few collumns have a large number of NAs
    x <- x[colSums(is.na(x))/nrow(x) <.97]
        
    # remove observations/rows with over a certain % of NAs
    summary(rowSums(is.na(x))/ncol(x))
    
    #check that all is fine
    if(!anyNA(x)) 
        print("no NAs in x")
    return(x)
    }
    

# training_cl1 <- training
# training_cl1[training_cl1 == "" |training_cl1 == "#DIV/0!" ] <- NA
# testing_cl1 <- training
# testing_cl1[training_cl1 == ""] <- NA
# 
# # Cleaning the dataset to remove irelevant observations (rows), e.g. all NAs, output(classe) = NA
# training_cl2 <- training_cl1[!complete.cases(training_cl1),] #<---------
# training_cl3 <- training_cl2[training_cl2$classe != "NA",]
# 
# testing_cl2 <- testing_cl1[!complete.cases(testing_cl1),] #<------
# testing_cl3 <- testing_cl2[testing_cl2$classe != "NA",]
# 
# 
# # Cleaning the dataset to remove irrelevant variables (columns), e.g. < 97% blanks or NAs, there are some columns that are always NA when the variable new_window = "no"
# training_cl4 <- training_cl3
# training_cl4 <- training_cl3[, colSums(is.na(training_cl3))/nrow(training_cl3) < .95]
# training_cl5 <- dplyr::select(training_cl4, -X, -user_name, -raw_timestamp_part_1, -raw_timestamp_part_2, -cvtd_timestamp, -new_window, -num_window)
# 
# testing_cl4 <- testing_cl3
# testing_cl4 <- testing_cl3[, colSums(is.na(testing_cl3))/nrow(testing_cl3) < .95]
# # remove variables/columns considered irrelevant for study
# testing_cl5 <- dplyr::select(testing_cl4, -X, -user_name, -raw_timestamp_part_1, -raw_timestamp_part_2, -cvtd_timestamp, -new_window, -num_window)

training_cl <- clean(training)
testing_cl <- clean(testing)
dim(training_cl) 
dim(testing_cl)


# training_cl2 <- training[rbind(colnames(training[nearZeroVar(training, saveMetrics =TRUE, names = TRUE)$nzv]), "classe")]
# training_cl2 <- clean2(training)
# testing_cl2 <- clean2(testing)
# dim(training_cl2) 
# dim(testing_cl2)


# remove variables/columns considered irrelevant for study
testing_cl <- dplyr::select(testing_cl, -X, -user_name, -raw_timestamp_part_1, -raw_timestamp_part_2, -cvtd_timestamp, -new_window, -num_window)
training_cl <- dplyr::select(training_cl, -X, -user_name, -raw_timestamp_part_1, -raw_timestamp_part_2, -cvtd_timestamp, -new_window, -num_window)

dim(training_cl)
# <----------- Esto se puede poner dentro de una función y llamarla  2 veces

```
That leaves us with a smaller dataset (`r dim(training_cl)[1]` observations and `r dim(training_cl)[2]` variables), in principle equally relevant in modelling terms, and easier to work with in terms of performance.

We decided to keep the test dataset for final validation, and subdivide the clean training set into a training set and a test set, so that we can assess out of sample error. The table below represents the different sets: 


```{r, prepare-data-sets, cache=TRUE, echo=FALSE}
# Creating working sets
inTrain <- createDataPartition(y=training_cl$classe, times = 1, p=0.998,list = FALSE)
train <- training_cl[inTrain,]
test <- training_cl[-inTrain,]
validate <- testing_cl

##############
anyNA(train)
anyNA(test)
anyNA(validate)
table <- xtable(
    matrix(c(dim(training), dim(testing), dim(training_cl), dim(train), dim(test), dim(validate)), 
           ncol = 6, byrow = FALSE,
           dimnames = list(c("Observations", "Variables"), c("Original training dataset", "Original testing","Clean Training dataset", "Train set", "Test set","Validate set"))),
    caption = "Original datasets",
    auto = TRUE)
#align = c("lll|lll"))
panderOptions('table.split.table', Inf)
pander(table)
```

##Data Exploration

Considering the *train set*, we'll start by checking the number of variables with zero variance (0). Then we study how interrelated variables are (see figure below):
```{r, explore-data1, cache=TRUE, echo=FALSE, fig.width=8, fig.height=8}
# Study correlations between variables to select those most significant to predict classe
# dim(train)
# head(train)
zero_var <- sum(nearZeroVar(select(train, -classe), saveMetrics =TRUE, names = TRUE)$nzv)

cor <- cor(select(train, -classe))
corrplot(cor, method="color", type = "lower", tl.srt=45, tl.cex =.7, tl.col="black")

#<---------- REMOVE
#######################
# getting a slice of the train dataset to optimise execution time in first trials
inTrain2 <- createDataPartition(y=train$classe, times = 1, p=0.01,list = FALSE)
trainx <- train[inTrain2,]

anyNA(trainx)


```

Considering the number of dark cells, a Principal Components analysis can help us identify the main variables to consider in the model, to reduce its complexity (and execution/training time). The negative values make a logaritmic transformation useless, so we proceed considering scaling and centering options. We combine the PCA preprocessing with a random forest model.
```{r, explore_pca_rf, cache=TRUE, echo=FALSE, fig.width=8, fig.height=8}
system.time({
# create preprocess object
preProc <- preProcess(select(train, -classe), method="pca", thresh =.98) # calculate PCs for training data
train_pca <- predict(preProc, select(train, -classe))
# run model on outcome and principle components
fit_pca_rf <- train(train$classe ~ ., data = train_pca, method = "rf") # calculate PCs for test data
pred_pca_rf <- predict(fit_pca_rf,select(test, -classe))
# compare results 
confusionMatrix(test$classe,pred_pca_rf)
})
````


<------- pendiente revisar crosvarianza, se puede hacer dentro del random fores
```{r, explore_fit_rf, cache=TRUE, echo=FALSE, fig.width=8, fig.height=8}
# fit using subset
system.time({fit_rfx <- randomForest(classe ~., data = trainx)})
system.time({fit_rf <- randomForest(classe ~., data = train)})
system.time({fit_rf_caret <- train(classe ~., data = train, trControl=trainControl(method="cv",number=10, repeats=1))})

# predict for both cases
pred_rfx <- predict(fit_rfx, test)
pred_rf <- predict(fit_rf, test)
pred_rf_caret <- predict(fit_rf_caret, test)
# obtain accuracy
confusionMatrix(pred_rfx, test$classe)$overall[1]
confusionMatrix(pred_rf, test$classe)$overall[1]
confusionMatrix(pred_rf_caret, test$classe)$overall[1]
```
```{r, explore-data2, cache=TRUE, echo=FALSE, fig.width=8, fig.height=8}

pr<-prcomp(trainy, scale = TRUE)
plot(pr, type = "l")
summary(pr)

# g <- ggplot(pr, aes(y = mpg, x = am, color = am)) +
#     geom_point(shape = 21, size = 3, fill ="darkblue") +
#     scale_color_gradient(low="orange", high="green") +
#     geom_smooth(method = lm, se = FALSE, colour = "black")  +
#     xlab("transmission (0:auto)") + ylab("range (mpg)") +
#     font_theme
# g

plot(pr, type = "l")

#tree <- train(classe ~., method ="rpart", data = train)
# fancyRpartPlot(tree$finalModel)

#fit1 <- randomForest(y = train$classe, x = train)


# train allows to specify how to deal with cross validation, document!!!!!!!!

```


##We will consider models that with independence of the internal treatment that some models already consider (e.g. random forest)


## Analysis

## Conclusions

\newpage
## References

In this project, your goal will be to use data from accelerometers on the belt, forearm, arm, and dumbell of 6 participants. They were asked to perform barbell lifts correctly and incorrectly in 5 different ways.

The goal of your project is to predict the manner in which they did the exercise. This is the "classe" variable in the training set. You may use any of the other variables to predict with. You should create a report describing how you built your model, how you used cross validation, what you think the expected out of sample error is, and why you made the choices you did. You will also use your prediction model to predict 20 different test cases.

