function dmodel = add_noisedipole(N,fs,ntype,epos,noisepos,debug)
% this function is used to generate realistic noise. The MA, EM and BW
% files from the Physionet NSTDB can be used for that purpose. However there are
% three main limitations when using these records; 1. their length is
% limited (thus if we only use these records then we will re-use them or part 
% of them when generating multiple noise segments), 
% 2. there are only two channels available (if we want to model 
% noise on the VCG then we need three) and 3. this is noise from one
% individual only.
% In order to tackle these problems we propose to use an AR model
% to describes the noisy time-varying processe. An AR model can be viewed 
% as the output of an all-pole infinite impulse response filter with input 
% white noise. We learn these coefficients on a randomly selected segment 
% of one of the NSTDB signals. This defines filter coefficients with 
% associated frequency response. In order to account for the uniqueness 
% of the records available in the NSTDB and integrate some variability, the 
% poles, of the learned AR filter, are slightly randomly shifted while
% unsuring they stay in the unit cicle.
%
% inputs
%   N:      size of the noise to generate at fs (sampling frequency) [datapoint number]
%   ntype:  type of noise to generate (MA,EM or BW) [string]
%   fs:     sampling frequency [Hz]
%   debug:  debug mode level [integer]
%
% output
%     dmodel   structure contaning dipole model i.e.:
%        dmodel.H      - Dower-like matrix for dipole (assuming time invariance)
%        dmodel.VCG    - VCG for dipole
%        dmodel.type   - always 3 (noise dipole)
%        dmodel.SNRfct - function which modulates SNR of noise. E.g. 
%                             sin(linspace(-pi,pi,N)
% 
% NI-FECG simulator toolbox, version 1.0, February 2014
% Released under the GNU General Public License
%
% Copyright (C) 2014  Joachim Behar & Fernando Andreotti
% Oxford university, Intelligent Patient Monitoring Group - Oxford 2014
% joachim.behar@eng.ox.ac.uk, fernando.andreotti@mailbox.tu-dresden.de
%
% Last updated : 03-06-2014
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with this program.  If not, see <http://www.gnu.org/licenses/>.

% == manage inputs
if nargin<2; error('add_noisedipole: not enough input arguments'); end;
if isempty(ntype); ntype ='MA'; end;
if nargin<5; error('add_noisedipole: not enough input arguments'); end;
if nargin<6; debug=0; end;

% == some checking
if sum(find(strcmp(ntype,{'MA','EM','BW'})))==0; error('add_noisedipole: this noise type is not supported \n'); end;
    
% == constants
AR_ORDER = 12; % number of poles
FS_NSTDB = 360; % sampling frequency of NSTDB
LG_NSTDB = FS_NSTDB*29; % number of points in NSTDB
NP_NSTDB = 20*FS_NSTDB; % number of points to select in NSTDB records to generate the AR coefficients
N_SAMP = floor(N/(fs/FS_NSTDB)); % N samples at fs correspond to N_SAMP at FS_NSTDB
NB_EL = size(epos,1); % number of electrodes

% == randomly select noise interval of size LG_SEL
start = round(LG_NSTDB*rand);
stop = start + NP_NSTDB;

MA = []; EM = []; BW = [];
% == select type of noise
if strcmp('MA',ntype)
    load('MA.mat'); noise = MA(start:stop-1,:);
elseif strcmp('EM',ntype)
    load('EM.mat'); noise = EM(start:stop-1,:);
elseif strcmp('BW',ntype)
    load('BW.mat'); noise = BW(start:stop-1,:);
else
        error('Noise inexistent.')
end
% == removing baseline from MA and EM: this is because most of the noise 
% power added to the ECG mixture might be contained in the baseline which 
% is easier to remove than MA/EM noise. So the MA and EM noise are
% considered baseline-free and some baseline (BW) noise can be speficied on
% top by the user.
if strcmp('MA',ntype) || strcmp('EM',ntype)
    [B,A] = butter(5,1*2/fs,'high'); % high-pass filter with 1 Hz
    noise(:,1) = filtfilt(B,A,noise(:,1));
    noise(:,2) = filtfilt(B,A,noise(:,2));
end

% == AR model
x = randn(N_SAMP+AR_ORDER,2); % generating random signal to be filtered by AR model
a = zeros(AR_ORDER,N_SAMP+AR_ORDER); % allocating
noise_ar = zeros(N,3);
y = zeros(N_SAMP+AR_ORDER,1);          
st = -0.001; % start
ed = 0.001; % end
rdNb = st + (ed-st).*rand(AR_ORDER,2*N,2); % generate rd number in [st ed]
                                           % generating for both noise channels
for cc=1:2
    % for each channel vary the poles in the same fashion
    [atemp,~] = aryule(noise(:,cc),AR_ORDER); % a global AR model
    a(:,1) = atemp(2:end)'; % first is always 1
    rinit = roots(atemp); % gets the poles
    ainit = atemp;
    % evolving AR model
    for ev=2:N_SAMP+AR_ORDER
        r = roots(atemp); % gets the poles
        sImg = imag(r);
        sRea = real(r);
        dz = diag(sRea)*rdNb(:,(cc-1)*N+ev,1) + diag(sImg)*rdNb(:,(cc-1)*N+ev,2).*1i;
        pn = r + dz; % varying the poles
        ind = find(abs(rinit - pn)>0.05); % constrain the AR coeff not to move too far from initial coeff location
        pn(ind) = r(ind);
        indlim = find((sImg.^2+sRea.^2)>=0.99); % to unsure we do not get on/out the unit circle
        pn(indlim) = r(indlim);
        [~,atemp] = zp2tf(0,pn,1); % back to filter coefficients (gain set to 1)
        a(:,ev) = atemp(2:end);
    end
    for i = AR_ORDER+1:N_SAMP+AR_ORDER
        y(i) = x(i,cc)-a(:,i)'*y(i-1:-1:i-AR_ORDER);
    end
    y = y(AR_ORDER+1:end); % skipping initialisation
    noise_ar(:,cc) = resample((y-mean(y))/std(y),fs,FS_NSTDB); % resampling, zero mean and unit variance
end

% == produce third channel using PCA
[~,pc] = princomp(noise_ar);
noise_ar(:,3) = pc(:,1)/std(pc(:,1));

% == Generating projection matrix (here implying no translation of dipole)
den_norm = diag(1./sqrt(sum((epos-repmat(noisepos,NB_EL,1)).^2,2)).^3); % denominator's norm (from H equation)
H = den_norm*(epos-repmat(noisepos,NB_EL,1));     % projection matrix

% == formatting output
dmodel.VCG = noise_ar';     % noise VCG
dmodel.H = H;               % projection matrix
dmodel.type = 3;            % noise source

% == debug
if debug>0
    col = [1,0,0; % red
        0,0,1; % blue
        0,0.8,0; % green
        0.4,0.4,0; % dark yellow
        0,0.8,0.8; % cyan
        0.4,0,0.8; % dark magenta
        0.8,0.4,1; % light magenta
        0.4,0.4,1]; % lilac
    
    close all;
    FONT_SIZE = 15;
    LINE_WIDTH = 2;
    % == AR poles analysis
    % will plot the old and new poles for the last generated channel
    figure('name','Poles before and after being shifted');
    [~,hp_1,~] = zplane(1,roots([1 a(:,1)'])); 
    set(hp_1,'color','b','LineWidth',3,'MarkerSize',10);
    hold on, [~,hp_2,~] = zplane(1,roots([1 a(:,end)']));
    set(hp_2,'color','r','LineWidth',3,'MarkerSize',10,'Marker','o');

    set(gca,'FontSize',FONT_SIZE);
    set(findall(gcf,'type','text'),'fontSize',FONT_SIZE); 
    xlim([-1 1]); ylim([-1 1]);
end

if debug>1
    % == selected noise analysis
    figure('name','real noise');
    tm = 1/FS_NSTDB:1/FS_NSTDB:NP_NSTDB/FS_NSTDB;
    for cc=1:2
        subplot(2,1,cc); plot(tm,noise(:,cc),'color',col(cc,:),'LineWidth',LINE_WIDTH);
        xlim([0 10]);
        set(gca,'FontSize',FONT_SIZE);
        set(findall(gcf,'type','text'),'fontSize',FONT_SIZE); 
    end
    xlabel('Time [sec]'); ylabel('Amplitude [NU]');
    xlim([0 10]);
    set(gca,'FontSize',FONT_SIZE);
    set(findall(gcf,'type','text'),'fontSize',FONT_SIZE);    
end


if debug>2
   % == plot the noise generate using AR model and PCA
    figure('name','AR+PCA generated noise');
    tm = 1/fs:1/fs:N/fs;
    for cc=1:3
        subplot(3,1,cc); plot(tm,noise_ar(:,cc),'color',col(cc,:),'LineWidth',LINE_WIDTH);
        xlim([0 10]);
        set(gca,'FontSize',FONT_SIZE);
        set(findall(gcf,'type','text'),'fontSize',FONT_SIZE); 
    end
    xlabel('Time [sec]'); ylabel('Amplitude [NU]');
    set(gca,'FontSize',FONT_SIZE);
    set(findall(gcf,'type','text'),'fontSize',FONT_SIZE);     
end

if debug>3
   % == power spectral density
   
   % = using the AR coeff computed here
   figure('name','Power Spectral Density plot');
   [h1,f1] = freqz(1,ainit,512,FS_NSTDB);
   P1 = abs(h1).^2; % power
   P1dB = 10*log10(P1/(mean(P1))); % power in decibels
   plot(f1,P1dB,'LineWidth',LINE_WIDTH);

   [h2,f2] = freqz(1,[1; mean(a,2)],512,FS_NSTDB);
   P2 = abs(h2).^2;
   P2dB = 10*log10(P2/(mean(P2)));
   hold on, plot(f2,P2dB,'--r','LineWidth',LINE_WIDTH);
   
   xlabel('Frequency [Hz]');
   ylabel('Power [db]');
   set(gca,'FontSize',FONT_SIZE);
   set(findall(gcf,'type','text'),'fontSize',FONT_SIZE);   
   legend('initial AR coefficients','average AR coefficients');
   box off;
   legend boxoff;
   % = using pwelch
   %figure('name','Power Spectral Density plot');
   %leg{1} = 'NSTDB segment PSD';
   %leg{2} = 'AR segment PSD';
   %plot_psd(noise(:,1),y(:,1),FS_NSTDB,'welch',leg);
end

