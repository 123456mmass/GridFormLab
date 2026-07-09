function ConfirmEigenanalysis(StateSpaceFile,EigenResultFile)

% Matlab code to confirm that Mudpack and Matlab eigenanalysis results are consistent.

Model = load(StateSpaceFile);
Eigen = load(EigenResultFile);

% Confirm that the dimensions of the state matrix and the eigenvalue vector are the same.

if (size(Model.AA,1) ~= size(Eigen.E,1))
   error(['The state-space model and eigenanalysis results are inconsistent ', ...
          'because the number of states and eigenvalues are not the same.']);
end

% 
% Sort the Mudpack eigenvalues into ascending order and permute
% the columns of V,W & P according to this ordering

[Eigen.E,JJ_MP] = sort(Eigen.E);
Eigen.V = Eigen.V(:,JJ_MP);
Eigen.W = Eigen.W(:,JJ_MP);
Eigen.P = Eigen.P(:,JJ_MP);

% Perform eigenanalysis on the system state-matrix using Matlab

[V,E] = eig(Model.AA);
E = diag(E);
W = (V\eye(size(V))).'; % '
P = V.*W;

% Sort the Matlab eigenvalues into ascending order and permute the
% columns of V, W & P according to this ordering.

[E,JJ_ML] = sort(E);
V = V(:,JJ_ML);
W = W(:,JJ_ML);
P = P(:,JJ_ML);

% Compare the eigenanalysis results computed by Matlab and Mudpack. 

% (1) Eigenvalue comparison

tol = sqrt(eps);
ii = find(abs(E - Eigen.E) > tol);
if (isempty(ii))
   MXERR = max(abs(E - Eigen.E));
   fprintf(['The maximum difference between the Mudpack and Matlab eigenvalues is %13.4g ', ...
            'which is less than the specified tolerance of %13.4g\n'],MXERR,tol);
else
   str = sprintf(['\nAn inconsistency between the eigenvalues computed by Mudpack ', ...
   'and Matlab has been detected.\n\n']);
   str = [ str sprintf('Mode     Mudpack Eigenvalues      |     Matlab Eigenvalues\n') ];
   str = [ str sprintf('         Real         Imaginary   |     Real         Imaginary\n') ];
   for i = 1:length(ii)
      k = ii(i);
      str = [str sprintf('%4d  %13.4g %13.4g | %13.4g %13.4g\n', ...
                 k,real(Eigen.E(k)),imag(Eigen.E(k)), ...
                   real(E(k)),imag(E(k)))];
   end
   error(str);
end


% Employ a wider tolerance when assessing consistency of eigenvectors and participation factors

tol = 100*sqrt(eps);

% (2) Right eigenvector comparison

CompareMatrices(V,Eigen.V,tol,'right-eigenvectors');

% (3) Left eigenvector comparison

CompareMatrices(W,Eigen.W,tol,'left-eigenvectors');

% (4) Participation factor comparison.

CompareMatrices(P,Eigen.P,tol,'participation factors');


function CompareMatrices(X_ML,X_MP,tol,Name)

   % Prior to comparing the elements in corresponding columns of the Matlab
   % and Mudpack matrices the columns are normalized with respect to the element
   % with the largest amplitude in the column.

   n = size(X_ML,2);
   MXERR = 0;
   for i = 1:n
   
      [dum,MX_ML] = max(abs(X_ML(:,i)));
      [dum,MX_MP] = max(abs(X_MP(:,i)));
   
      XC_ML = X_ML(:,i)/X_ML(MX_ML,i);
      XC_MP = X_MP(:,i)/X_MP(MX_MP,i);
   
      MXERR = max([MXERR,max(abs(XC_ML - XC_MP))]);
   
   end
   
   if (MXERR > tol)
      error(sprintf(['The maximum difference between the Mudpack and Matlab ' Name ' is %13.4g ', ...
            'which exceeds the specified tolerance of %13.4g\n'],MXERR,tol));
   else
      fprintf(['The maximum difference between the Mudpack and Matlab ' Name ' is %13.4g ', ...
               'which is less than the specified tolerance of %13.4g\n'],MXERR,tol);
   end

