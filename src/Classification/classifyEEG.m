function [CM, accuracy, classifierInfo] = classifyEEG(X, Y, varargin)
% -------------------------------------------------------------
% Blair - Feb. 22, 2017
%
% The main function for sorting user inputs and calling classifier.

% Initialize the input parser
ip = inputParser;
ip.CaseSensitive = false;

%Specify default values
defaultNormalize = 'diagonal';
defaultShuffleData = 0;
defaultAverageTrials = 10;
defaultPermutationTest = 0;
defaultPCA = .9;
defaultFolds = 10;
defaultClassify = 0;

%Specify expected values
expectedNormalize = {'diagonal', 'sum', 'none'};
expectedShuffleData = [0, 1];
expectedPermutationTest = 0;
expectedPCA = 0;
expectedFolds = 10;
expectedClassify = 0;

%Required inputs
addRequired(ip, 'X', @ismatrix)
addRequired(ip, 'Y', @isvector)

%Optional positional inputs
%addOptional(ip, 'distpower', defaultDistpower, @isnumeric);
addParameter(ip, 'shuffleData', defaultShuffleData, ...
    @(x) any(validatestring(x, expectedShuffleData)));
addParameter(ip, 'averageTrials', defaultAverageTrials, ...
    @(x) assert(rem(x,1) == 0 ));
addParameter(ip, 'permutationTest', defaultPermutationTest, ...
     @(x) any(validatestring(x, expectedPermutationTest)));
addParameter(ip, 'doPCA', defaultPCA, ...
    @(x) assert(rem(x,1) == 0 ));

%Optional name-value pairs
%NOTE: Should use addParameter for R2013b and later.
addParameter(ip, 'normalize', defaultNormalize,...
    @(x) any(validatestring(x, expectedNormalize)));

% Parse
parse(ip, X, Y, varargin{:});

% X3 = randi(12, [5 3 10]);
% X2 = randi(12, [10 15]);
% Y = randi(20, [10 1])';
% X = X3;
featureUse = []; spaceUse = []; timeUse = [];

%%%%% INPUT DATA CHECKING (doing)
%%% Check the input data matrix X
if ndims(X) == 3
    [nSpace, nTime, nTrials] = size(X);
    disp(['Input data matrix size: ' num2str(nSpace) ' space x ' ...
        num2str(nTime) ' time x ' num2str(nTrials) ' trials'])
elseif ndims(X) == 2
    [nTrials, nFeature] = size(X);
    warning(['2D input data matrix. Assuming '...
        num2str(nTrials) ' trials x ' num2str(nFeature) ' features.'])
else
    error('Input data matrix should be 3D or 2D matrix.')
end
%%% Check the input labels vector Y
if ~isvector(Y)
    error('Input labels vector must be a vector.')
elseif length(Y) ~= nTrials
    error(['Length of input labels vector must correspond '...
        'to number of trials (' num2str(nTrials) ').'])
end
% Convert to column vector if needed
if ~iscolumn(Y)
   warning('Transposing input labels vector to column.') 
   Y = Y(:);
end

%%%%% INPUT DATA SUBSETTING (doing)
% Default chanUse, timeUse, featureUse = [ ]
%%% 3D input matrix
X_subset = X; % This will be the next output; currently 3D or 2D
if ndims(X) == 3
    % Message about ignoring 'featureUse' input
   if ~isempty(featureUse)
       warning('Ignoring ''featureUse'' for 3D input data matrix.')
       warning('Use ''spaceUse'' and ''timeUse'' for 3D input data matrix.')
   end
   
   % If the user did specify a spatial or temporal subset...
   if ~isempty(spaceUse) || ~isempty(timeUse)
       % Confirm that spaceUse and timeUse are vectors
       if (~isempty(spaceUse) && ~isvector(spaceUse)) ||...
               (~isempty(timeUse) && ~isvector(timeUse))
           error('Enter a vector to specify spatial and/or temporal subsets.')
       end
       
       % Confirm that spaceUse and timeUse fit dimensions of data matrix
       if ~isempty(spaceUse) && ~all(ismember(spaceUse, 1:nSpace))
           error('''spaceUse'' input is not contained in the input data matrix.')
       elseif ~isempty(timeUse) && ~all(ismember(timeUse, 1:nTime))
           error('''timeUse'' input is not contained in the input data matrix.')
       end
       
       % Do the subsetting
       if ~isempty(spaceUse)
           X_subset = X_subset(spaceUse, :, :);
       end
       if ~isempty(timeUse)
           X_subset = X_subset(:, timeUse, :);
       end
       
       % Update nSpace and nTime
       nSpace = size(X_subset, 1);
       nTime = size(X_subset, 2);
   end
   % Reshape the X_subset matrix
   %X_subset = cube2toRows(X_subset); % NOW IT'S 2D
   
%%% 2D input matrix
elseif ndims(X) == 2
    % Messages about ignoring 'spaceUse' and/or 'timeUse' inputs
    if ~isempty(spaceUse) || ~isempty(timeUse)
       if ~isempty(spaceUse)
           warning('Ignoring ''spaceUse'' for 2D input data matrix.')
       end
       if ~isempty(timeUse)
           warning('Ignoring ''timeUse'' for 2D input data matrix.')
       end
       warning('Use ''featureUse'' for 2D input data matrix.')
    end
    
    % If the user specified a featureUse subset...
    if ~isempty(featureUse)
        % Confirm it's a vector
        if ~isvector(featureUse)
           error('Enter a vector to specify feature subsets.') 
        end
        
       % Confirm that featureUse is contained in the data matrix
       if ~all(ismember(featureUse, 1:nFeature))
          error('''featureUse'' input is not contained in the input data matrix.') 
       end
       
       % Do the subsetting
       X_subset = X_subset(:, featureUse);  % WAS ALREADY 2D
       
       % Update nFeature
       nFeature = size(X_subset, 2);
    end  
end
X = X_subset;

%%%%% Whatever we started with, we now have a 2D trials-by-feature matrix
% moving forward.

% DATA SHUFFLING (doing)
% Default 1
if ~(isempty(ip.Results.shuffleData))
    if (ip.Results.shuffleData)
        [X, Y] = shuffleData(X, Y);
    end
end

% TRIAL AVERAGING (doing)
 if ~(isempty(ip.Results.averageTrials))
    [X, Y] = averageTrials(X, Y, ip.Results.averageTrials);
 end


% PERMUTATION TEST (assigning)
% Default 0
% If doPermTest
%   (details are TODO)
%   Get integer number of permutation iterations

% PCA PARAMS (assigning)
 if ~(isempty(ip.Results.doPCA))
    X = getPCs(X, ip.Results.doPCA);
 end
 

% CROSS VALIDATION (assigning)
% Default 10
[r c] = size(X);

cvpartition(r, 'Kfold', ip.Results.folds);


% Just partition, as shuffling (or not) was handled in previous step
% if nFolds == 1
%   Special case of fitting model with no test set (argh)
% if nFolds < 0 | ceil(nFolds) ~= floor(nFolds) | nFolds > nTrials
%   error, nFolds must be an integer between 2 and nTrials to perform CV

% CLASSIFIER PARAMETERS (assigning)
% Default: SVM, rbf
% If SVM
%   Kernel options: linear, polynomial, rbf/gaussian (default), sigmoid
% If LDA
%   Discrimtype: linear (default), quadratic, diagLinear, diagQuadratic,
%   pseudoLinear, pseudoQuadratic
% If RF
%   nTrees: ?? (default), o.w. ?? other stuff
%   