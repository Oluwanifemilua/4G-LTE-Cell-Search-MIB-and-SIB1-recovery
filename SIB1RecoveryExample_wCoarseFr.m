%% Cell Search, MIB and SIB1 Recovery 
% This example shows how the LTE Toolbox(TM) can be used to fully
% synchronize, demodulate and decode a live eNodeB signal. Before the User
% Equipment (UE) can communicate with the network it must perform cell
% search and selection procedures and obtain initial system information.
% This involves acquiring slot and frame synchronization, finding out the
% cell identity and decoding the Master Information Block (MIB) and the
% System Information Blocks (SIBs). This example demonstrates this process
% and decodes the MIB and SIB1, the first of the System Information Blocks.
% To decode MIB and SIB1 a comprehensive receiver is required, capable of
% demodulating and decoding the majority of the downlink channels and
% signals.

% Copyright 2010-2019 The MathWorks, Inc.

%% Introduction
% In order to communicate with the network the UE must obtain some basic
% system information. This is carried by the MIB and SIBs. The MIB carries
% the most essential system information:
%
% * System bandwidth
% * System Frame Number (SFN)
% * Physical Hybrid Automatic Repeat Request (HARQ) Indicator Channel
% (PHICH) Configuration
%
% The MIB is carried on the Broadcast Channel (BCH) mapped into the
% Physical Broadcast Channel (PBCH). This is transmitted with a fixed
% coding and modulation scheme and can be decoded after the initial cell
% search procedure. With the information obtained from the MIB the UE can
% now decode the Control Format Indicator (CFI), which indicates the
% Physical Downlink Control Channel (PDCCH) length. This allows the PDCCH
% to be decoded, and searched for Downlink Control Information (DCI)
% messages. A DCI message CRC masked with System Information Radio Network
% Temporary Identifier (SI-RNTI) indicates that a SIB is carried in the
% same subframe. The SIBs are transmitted in the Broadcast Control Channel
% (BCCH) logical channel. Generally, BCCH messages are carried on the
% Downlink Shared Channel (DL-SCH) and transmitted on the Physical Downlink
% Shared Channel (PDSCH). The format and resource allocation of the PDSCH
% transmission is indicated by a DCI message on the PDCCH.
% 
% This example decodes the MIB and SystemInformationBlockType1 (SIB1). The
% latter is transmitted to specify the scheduling of other system
% information, along with aspects of the cell identity such as Public Land
% Mobile Network (PLMN) identity. Although SIB1 is transmitted in a fixed
% time schedule, the resource allocation of the PDSCH carrying SIB1 is
% dynamic and is indicated in an associated DCI message. 

%% Load and Process I/Q Waveform 
% MATLAB(R) can be used to acquire I/Q data from a wide range of
% instruments using the Instrument Control Toolbox(TM). In this example a
% single antenna I/Q capture of an eNodeB with two transmit antennas is
% used. The capture is performed at 15.36 Msamples/s which is sufficient to
% correctly sample all valid eNodeB bandwidths up to 10 MHz: 1.4 MHz, 3
% MHz, 5 MHz, 10 MHz. The captured data is stored in the file
% eNodeBOutput.mat.
%
% Alternatively, a suitable LTE signal can be generated using the
% LTE Toolbox. This can be controlled by the variable |loadFromFile|.

loadFromFile = 1; % Set to 0 to generate the eNodeB output locally

%%
% The MIB corresponds to one BCH transport block. The BCH Transmission Time
% Interval (TTI), or the time needed to transmit a single transport block,
% is 40msec or 4 frames. The BCH is transmitted in 4 parts, each part
% mapped to the first subframe (subframe 0) of a frame and it is possible
% that each transmission is independently decodable, depending on signal
% conditions. To ensure that subframe 0 is received, the capture should be
% at least 11 subframes long, to account for the possibility that the
% capture is started during subframe 0. For poor signal conditions, all
% 4 parts of the TTI may be required, in which case the capture should be
% at least 41 subframes long. A similar situation applies for SIB1; it is
% transmitted in subframe 5 of every even frame, with four different
% Redundancy Versions (RVs) being transmitted consecutively giving an
% overall period of 80msec or 8 frames. Therefore 21 subframes of capture
% are required to ensure reception of a single RV of SIB1 (in subframe 5 of
% an even frame), but up to 81 subframes of capture are required if signal
% conditions are such that all RVs need to be combined. 

if loadFromFile
%     load eNodeBOutput.mat           % Load I/Q capture of eNodeB output
%     eNodeBOutput = double(eNodeBOutput)/32768; % Scale samples
%     sr = 15.36e6;                   % Sampling rate for loaded samples

    BBR = comm.BasebandFileReader('B28LTEcapture.bb'); % Create a baseband file reader object
    bbrInfo = info(BBR);
    BBR.SamplesPerFrame = bbrInfo.NumSamplesInData; % Number of sample in the waveform
    eNodeBOutput = BBR();  % Load the I&Q sample from a binary file
    sr = BBR.SampleRate; % Sampling rate of the input signal
    release(BBR);

else
    rmc = lteRMCDL('R.3'); %#ok<UNRCH>
    rmc.NCellID = 17;
    rmc.TotSubframes = 41;
    rmc.PDSCH.RNTI = 61;
    % SIB parameters
    rmc.SIB.Enable = 'On';
    rmc.SIB.DCIFormat = 'Format1A';
    rmc.SIB.AllocationType = 0;
    rmc.SIB.VRBStart = 8;
    rmc.SIB.VRBLength = 8;
    rmc.SIB.Gap = 0;
    % SIB data field filled with random bits, this is not a valid SIB
    % message
    rmc.SIB.Data = randi([0 1],176,1);
    [eNodeBOutput,~,info] = lteRMCDLTool(rmc,[1;0;0;1]);
    sr = info.SamplingRate;     % Sampling rate of generated samples
end

%%
% Prior to decoding the MIB, the UE does not know the full system
% bandwidth. The primary and secondary synchronization signals (PSS and
% SSS) and the PBCH (containing the MIB) all lie in the central 72
% subcarriers (6 resource blocks) of the system bandwidth, allowing the UE
% to initially demodulate just this central region. Therefore the bandwidth
% is initially set to 6 resource blocks. The I/Q waveform needs to be
% resampled accordingly. At this stage we also display the spectrum of the
% input signal |eNodeBOutput|.

% Set up some housekeeping variables:
% separator for command window logging
separator = repmat('-',1,50);
% plots
if (~exist('channelFigure','var') || ~isvalid(channelFigure))
    channelFigure = figure('Visible','off');        
end
[spectrumAnalyzer,synchCorrPlot,pdcchConstDiagram] = ...
    hSIB1RecoveryExamplePlots(channelFigure,sr);
% PDSCH EVM
pdschEVM = comm.EVM();
pdschEVM.MaximumEVMOutputPort = true;

% The sampling rate for the initial cell search is established using 
% lteOFDMInfo configured for 6 resource blocks. enb.CyclicPrefix is set
% temporarily in the call to lteOFDMInfo to suppress a default value
% warning (it does not affect the sampling rate).
enb = struct;                   % eNodeB config structure
enb.NDLRB = 6;                  % Number of resource blocks
ofdmInfo = lteOFDMInfo(setfield(enb,'CyclicPrefix','Normal')); %#ok<SFLD>

if (isempty(eNodeBOutput))
    fprintf('\nReceived signal must not be empty.\n');
    return;
end

% Display received signal spectrum
fprintf('\nPlotting received signal spectrum...\n');
spectrumAnalyzer(awgn(eNodeBOutput, 100.0));

if (sr~=ofdmInfo.SamplingRate)
    if (sr < ofdmInfo.SamplingRate)
        warning('The received signal sampling rate (%0.3fMs/s) is lower than the desired sampling rate for cell search / MIB decoding (%0.3fMs/s); cell search / MIB decoding may fail.',sr/1e6,ofdmInfo.SamplingRate/1e6);
    end
    fprintf('\nResampling from %0.3fMs/s to %0.3fMs/s for cell search / MIB decoding...\n',sr/1e6,ofdmInfo.SamplingRate/1e6);
else
    fprintf('\nResampling not required; received signal is at desired sampling rate for cell search / MIB decoding (%0.3fMs/s).\n',sr/1e6);
end
% Downsample received signal
nSamples = ceil(ofdmInfo.SamplingRate/round(sr)*size(eNodeBOutput,1));
nRxAnts = size(eNodeBOutput, 2);
downsampled = zeros(nSamples, nRxAnts);
for i=1:nRxAnts
    downsampled(:,i) = resample(eNodeBOutput(:,i), ofdmInfo.SamplingRate, round(sr));
end

%% Cell Search, Cyclic Prefix Length and Duplex Mode Detection
% Call <matlab:doc('lteCellSearch') lteCellSearch> to obtain the cell 
% identity and timing offset |offset| to the first frame head. The cell
% search is repeated for each combination of cyclic prefix length and
% duplex mode, and the combination with the strongest correlation allows
% these parameters to be identified. A plot of the correlation between the
% received signal and the PSS/SSS for the detected cell identity is 
% produced. The PSS is detected using time-domain correlation and the SSS
% is detected using frequency-domain correlation. Prior to SSS detection,
% frequency offset estimation/correction using cyclic prefix correlation is
% performed. The time-domain PSS detection is robust to small frequency
% offsets but larger offsets may degrade the PSS correlation.

fprintf('\nPerforming cell search...\n');

% Set up duplex mode and cyclic prefix length combinations for search; if
% either of these parameters is configured in |enb| then the value is
% assumed to be correct
if (~isfield(enb,'DuplexMode'))
    duplexModes = {'TDD' 'FDD'};
else
    duplexModes = {enb.DuplexMode};
end
if (~isfield(enb,'CyclicPrefix'))
    cyclicPrefixes = {'Normal' 'Extended'};
else
    cyclicPrefixes = {enb.CyclicPrefix};
end

% Coarse frequency estimation and correction:
% CP-based estimation can only detect +/-7.5kHz. Try +/-300kHz
% Note that if offset is larger, it would be better to first correct
% then downsample
fprintf('Coarse frequency offset estimation\n');
freqRange = -300000:5000:300000;
p_peaks = zeros(size(freqRange));
for foffsetNr = 1:numel(freqRange)
    foffset = freqRange(foffsetNr);    
    waveform = lteFrequencyCorrect(enb, downsampled, foffset);
    p_peaks(foffsetNr) = PSSpeak(enb,waveform);
end
% figure; plot(freqRange,p_peaks)
[~,indMax] = max(p_peaks);
coarseFreqOffset = freqRange(indMax);
fprintf('coarseFreqOffset = %.1f\n\n', coarseFreqOffset);

% Correct for coarse frequency offset on downsampled waveform
downsampled = lteFrequencyCorrect(enb, downsampled, coarseFreqOffset);    

% Perform cell search across duplex mode and cyclic prefix length
% combinations and record the combination with the maximum correlation; if
% multiple cell search is configured, this example will decode the first
% (strongest) detected cell
searchalg.MaxCellCount = 1;
searchalg.SSSDetection = 'PostFFT';
peakMax = -Inf;
for duplexMode = duplexModes
    for cyclicPrefix = cyclicPrefixes
        enb.DuplexMode = duplexMode{1};
        enb.CyclicPrefix = cyclicPrefix{1};
        [enb.NCellID, offset, peak] = lteCellSearch(enb, downsampled, searchalg);
        enb.NCellID = enb.NCellID(1);
        offset = offset(1);
        peak = peak(1);
        if (peak>peakMax)
            enbMax = enb;
            offsetMax = offset;
            peakMax = peak;
        end
    end
end

% Use the cell identity, cyclic prefix length, duplex mode and timing
% offset which gave the maximum correlation during cell search
enb = enbMax;
offset = offsetMax;

% Compute the correlation for each of the three possible primary cell
% identities; the peak of the correlation for the cell identity established
% above is compared with the peak of the correlation for the other two
% primary cell identities in order to establish the quality of the
% correlation.
corr = cell(1,3);
idGroup = floor(enbMax.NCellID/3);
for i = 0:2
    enb.NCellID = idGroup*3 + mod(enbMax.NCellID + i,3);
    [~,corr{i+1}] = lteDLFrameOffset(enb, downsampled);
    corr{i+1} = sum(corr{i+1},2);
end
threshold = 1.3 * max([corr{2}; corr{3}]); % multiplier of 1.3 empirically obtained
if (max(corr{1})<threshold)    
    warning('Synchronization signal correlation was weak; detected cell identity may be incorrect.');
end
% Return to originally detected cell identity
enb.NCellID = enbMax.NCellID;

% Plot PSS/SSS correlation and threshold
synchCorrPlot.YLimits = [0 max([corr{1}; threshold])*1.1];
synchCorrPlot([corr{1} threshold*ones(size(corr{1}))]);

% Perform timing synchronization
fprintf('Timing offset to frame start: %d samples\n',offset);
downsampled = downsampled(1+offset:end,:); 
enb.NSubframe = 0;

% Show cell-wide settings
fprintf('Cell-wide settings after cell search:\n');
disp(enb);

%%
%
% <<../CellSearch_MIB_SIB_PSS_SSS_Correlation.png>>

%% Frequency Offset Estimation and Correction
% Prior to OFDM demodulation, any significant frequency offset must be
% removed. The frequency offset in the I/Q waveform is estimated and
% corrected using <matlab:doc('lteFrequencyOffset') lteFrequencyOffset> and
% <matlab:doc('lteFrequencyCorrect') lteFrequencyCorrect>. The frequency
% offset is estimated by means of correlation of the cyclic prefix and
% therefore can estimate offsets up to +/- half the subcarrier spacing i.e.
% +/- 7.5kHz.

fprintf('\nPerforming frequency offset estimation...\n');
% For TDD, TDDConfig and SSC are defaulted to 0. These parameters are not
% established in the system until SIB1 is decoded, so at this stage the
% values of 0 make the most conservative assumption (fewest downlink
% subframes and shortest special subframe).
if (strcmpi(enb.DuplexMode,'TDD'))
    enb.TDDConfig = 0;
    enb.SSC = 0;
end
delta_f = lteFrequencyOffset(enb, downsampled);
fprintf('Frequency offset: %0.3fHz\n',delta_f);
downsampled = lteFrequencyCorrect(enb, downsampled, delta_f);    

%% OFDM Demodulation and Channel Estimation  
% The OFDM downsampled I/Q waveform is demodulated to produce a resource
% grid |rxgrid|. This is used to perform channel estimation. |hest| is the
% channel estimate, |nest| is an estimate of the noise (for MMSE
% equalization) and |cec| is the channel estimator configuration.
%
% For channel estimation the example assumes 4 cell specific reference
% signals. This means that channel estimates to each receiver antenna from
% all possible cell-specific reference signal ports are available. The true
% number of cell-specific reference signal ports is not yet known. The
% channel estimation is only performed on the first subframe, i.e. using
% the first |L| OFDM symbols in |rxgrid|.
%
% A conservative 13-by-9 pilot averaging window is used, in frequency and
% time, to reduce the impact of noise on pilot estimates during channel
% estimation.

% Channel estimator configuration
cec.PilotAverage = 'UserDefined';     % Type of pilot averaging
cec.FreqWindow = 13;                  % Frequency window size    
cec.TimeWindow = 9;                   % Time window size    
cec.InterpType = 'cubic';             % 2D interpolation type
cec.InterpWindow = 'Centered';        % Interpolation window type
cec.InterpWinSize = 1;                % Interpolation window size  

% Assume 4 cell-specific reference signals for initial decoding attempt;
% ensures channel estimates are available for all cell-specific reference
% signals
enb.CellRefP = 4;   
                    
fprintf('Performing OFDM demodulation...\n\n');

griddims = lteResourceGridSize(enb); % Resource grid dimensions
L = griddims(2);                     % Number of OFDM symbols in a subframe 
% OFDM demodulate signal 
rxgrid = lteOFDMDemodulate(enb, downsampled);    
if (isempty(rxgrid))
    fprintf('After timing synchronization, signal is shorter than one subframe so no further demodulation will be performed.\n');
    return;
end
% Perform channel estimation
[hest, nest] = lteDLChannelEstimate(enb, cec, rxgrid(:,1:L,:));

%% PBCH Demodulation, BCH Decoding, MIB Parsing
% The MIB is now decoded along with the number of cell-specific reference
% signal ports transmitted as a mask on the BCH CRC. The function
% <matlab:doc('ltePBCHDecode') ltePBCHDecode> establishes frame timing
% modulo 4 and returns this in the |nfmod4| parameter. It also returns the
% MIB bits in vector |mib| and the true number of cell-specific reference
% signal ports which is assigned into |enb.CellRefP| at the output of this
% function call. If the number of cell-specific reference signal ports is
% decoded as |enb.CellRefP=0|, this indicates a failure to decode the BCH.
% The function <matlab:doc('lteMIB') lteMIB> is used to parse the bit
% vector |mib| and add the relevant fields to the configuration structure
% |enb|. After MIB decoding, the detected bandwidth is present in
% |enb.NDLRB|. 

% Decode the MIB
% Extract resource elements (REs) corresponding to the PBCH from the first
% subframe across all receive antennas and channel estimates
fprintf('Performing MIB decoding...\n');
pbchIndices = ltePBCHIndices(enb);
[pbchRx, pbchHest] = lteExtractResources( ...
    pbchIndices, rxgrid(:,1:L,:), hest(:,1:L,:,:));

% Decode PBCH
[bchBits, pbchSymbols, nfmod4, mib, enb.CellRefP] = ltePBCHDecode( ...
    enb, pbchRx, pbchHest, nest); 

% Parse MIB bits
enb = lteMIB(mib, enb); 

% Incorporate the nfmod4 value output from the function ltePBCHDecode, as
% the NFrame value established from the MIB is the System Frame Number
% (SFN) modulo 4 (it is stored in the MIB as floor(SFN/4))
enb.NFrame = enb.NFrame+nfmod4;

% Display cell wide settings after MIB decoding
fprintf('Cell-wide settings after MIB decoding:\n');
disp(enb);

if (enb.CellRefP==0)
    fprintf('MIB decoding failed (enb.CellRefP=0).\n\n');
    return;
end
if (enb.NDLRB==0)
    fprintf('MIB decoding failed (enb.NDLRB=0).\n\n');
    return;
end

%% OFDM Demodulation on Full Bandwidth
% Now that the signal bandwidth is known, the signal is resampled to the
% nominal sampling rate used by LTE Toolbox for that bandwidth (see
% <matlab:doc('lteOFDMModulate') lteOFDMModulate> for details). Frequency
% offset estimation and correction is performed on the resampled signal.
% Timing synchronization and OFDM demodulation are then performed.

fprintf('Restarting reception now that bandwidth (NDLRB=%d) is known...\n',enb.NDLRB);

% Resample now we know the true bandwidth
ofdmInfo = lteOFDMInfo(enb);
if (sr~=ofdmInfo.SamplingRate)
    if (sr < ofdmInfo.SamplingRate)
        warning('The received signal sampling rate (%0.3fMs/s) is lower than the desired sampling rate for NDLRB=%d (%0.3fMs/s); PDCCH search / SIB1 decoding may fail.',sr/1e6,enb.NDLRB,ofdmInfo.SamplingRate/1e6);
    end    
    fprintf('\nResampling from %0.3fMs/s to %0.3fMs/s...\n',sr/1e6,ofdmInfo.SamplingRate/1e6);
else
    fprintf('\nResampling not required; received signal is at desired sampling rate for NDLRB=%d (%0.3fMs/s).\n',enb.NDLRB,sr/1e6);
end
nSamples = ceil(ofdmInfo.SamplingRate/round(sr)*size(eNodeBOutput,1));
resampled = zeros(nSamples, nRxAnts);
for i = 1:nRxAnts
    resampled(:,i) = resample(eNodeBOutput(:,i), ofdmInfo.SamplingRate, round(sr));
end

% Perform coarse frequency offset correction
resampled = lteFrequencyCorrect(enb, resampled, coarseFreqOffset);    

% Perform frequency offset estimation and correction
fprintf('\nPerforming frequency offset estimation...\n');
delta_f = lteFrequencyOffset(enb, resampled);
fprintf('Frequency offset: %0.3fHz\n',delta_f);
resampled = lteFrequencyCorrect(enb, resampled, delta_f);

% Find beginning of frame
fprintf('\nPerforming timing offset estimation...\n');
offset = lteDLFrameOffset(enb, resampled); 
fprintf('Timing offset to frame start: %d samples\n',offset);
% Aligning signal with the start of the frame
resampled = resampled(1+offset:end,:);   

% OFDM demodulation
fprintf('\nPerforming OFDM demodulation...\n\n');
rxgrid = lteOFDMDemodulate(enb, resampled);   

%% SIB1 Decoding
% The following steps are performed in this section:
%
% * Physical Control Format Indicator Channel (PCFICH) demodulation, CFI
% decoding
% * PDCCH decoding
% * Blind PDCCH search
% * SIB bits recovery: PDSCH demodulation and DL-SCH decoding
% * Buffering and resetting of the DL-SCH HARQ state
%
% After recovery the SIB CRC should be 0.
% 
% These decoding steps are performed in a loop for each occurrence of a
% subframe carrying SIB1 in the received signal. As mentioned above, the
% SIB1 is transmitted in subframe 5 of every even frame, so the input
% signal is first checked to establish that at least one occurrence of SIB1
% is present. For each SIB1 subframe, the channel estimate magnitude
% response is plotted, as is the constellation of the received PDCCH.

% Check this frame contains SIB1, if not advance by 1 frame provided we
% have enough data, terminate otherwise. 
if (mod(enb.NFrame,2)~=0)                    
    if (size(rxgrid,2)>=(L*10))
        rxgrid(:,1:(L*10),:) = [];   
        fprintf('Skipping frame %d (odd frame number does not contain SIB1).\n\n',enb.NFrame);
    else        
        rxgrid = [];
    end
    enb.NFrame = enb.NFrame + 1;
end

% Advance to subframe 5, or terminate if we have less than 5 subframes  
if (size(rxgrid,2)>=(L*5))
    rxgrid(:,1:(L*5),:) = [];   % Remove subframes 0 to 4        
else    
    rxgrid = [];
end
enb.NSubframe = 5;

if (isempty(rxgrid))
    fprintf('Received signal does not contain a subframe carrying SIB1.\n\n');
end

% Reset the HARQ buffers
decState = [];

% While we have more data left, attempt to decode SIB1
while (size(rxgrid,2) > 0)

    fprintf('%s\n',separator);
    fprintf('SIB1 decoding for frame %d\n',mod(enb.NFrame,1024));
    fprintf('%s\n\n',separator);

    % Reset the HARQ buffer with each new set of 8 frames as the SIB1
    % info may be different
    if (mod(enb.NFrame,8)==0)
        fprintf('Resetting HARQ buffers.\n\n');
        decState = [];
    end

    % Extract current subframe
    rxsubframe = rxgrid(:,1:L,:);
    
    % Perform channel estimation
    [hest,nest] = lteDLChannelEstimate(enb, cec, rxsubframe);    
    
    % PCFICH demodulation, CFI decoding. The CFI is now demodulated and
    % decoded using similar resource extraction and decode functions to
    % those shown already for BCH reception. lteExtractResources is used to
    % extract REs corresponding to the PCFICH from the received subframe
    % rxsubframe and channel estimate hest.
    fprintf('Decoding CFI...\n\n');
    pcfichIndices = ltePCFICHIndices(enb);  % Get PCFICH indices
    [pcfichRx, pcfichHest] = lteExtractResources(pcfichIndices, rxsubframe, hest);
    % Decode PCFICH
    cfiBits = ltePCFICHDecode(enb, pcfichRx, pcfichHest, nest);
    cfi = lteCFIDecode(cfiBits); % Get CFI
    if (isfield(enb,'CFI') && cfi~=enb.CFI)
        release(pdcchConstDiagram);
    end
    enb.CFI = cfi;
    fprintf('Decoded CFI value: %d\n\n', enb.CFI);   
    
    % For TDD, the PDCCH must be decoded blindly across possible values of 
    % the PHICH configuration factor m_i (0,1,2) in TS36.211 Table 6.9-1.
    % Values of m_i = 0, 1 and 2 can be achieved by configuring TDD
    % uplink-downlink configurations 1, 6 and 0 respectively.
    if (strcmpi(enb.DuplexMode,'TDD'))
        tddConfigs = [1 6 0];
    else
        tddConfigs = 0; % not used for FDD, only used to control while loop
    end    
    alldci = {};
    while (isempty(alldci) && ~isempty(tddConfigs))
        % Configure TDD uplink-downlink configuration
        if (strcmpi(enb.DuplexMode,'TDD'))
            enb.TDDConfig = tddConfigs(1);
        end
        tddConfigs(1) = [];        
        % PDCCH demodulation. The PDCCH is now demodulated and decoded
        % using similar resource extraction and decode functions to those
        % shown already for BCH and CFI reception
        pdcchIndices = ltePDCCHIndices(enb); % Get PDCCH indices
        [pdcchRx, pdcchHest] = lteExtractResources(pdcchIndices, rxsubframe, hest);
        % Decode PDCCH and plot constellation
        [dciBits, pdcchSymbols] = ltePDCCHDecode(enb, pdcchRx, pdcchHest, nest);
        pdcchConstDiagram(pdcchSymbols);

        % PDCCH blind search for System Information (SI) and DCI decoding.
        % The LTE Toolbox provides full blind search of the PDCCH to find
        % any DCI messages with a specified RNTI, in this case the SI-RNTI.
        fprintf('PDCCH search for SI-RNTI...\n\n');
        pdcch = struct('RNTI', 65535);  
        pdcch.ControlChannelType = 'PDCCH';
        pdcch.EnableCarrierIndication = 'Off';
        pdcch.SearchSpace = 'Common';
        pdcch.EnableMultipleCSIRequest = 'Off';
        pdcch.EnableSRSRequest = 'Off';
        pdcch.NTxAnts = 1;
        alldci = ltePDCCHSearch(enb, pdcch, dciBits); % Search PDCCH for DCI                
    end
    
    % If DCI was decoded, proceed with decoding PDSCH / DL-SCH
    for i = 1:numel(alldci)
        
        dci = alldci{i};
        fprintf('DCI message with SI-RNTI:\n');
        disp(dci);
        % Get the PDSCH configuration from the DCI
        [pdsch, trblklen] = hPDSCHConfiguration(enb, dci, pdcch.RNTI);
        
        % If a PDSCH configuration was created, proceed with decoding PDSCH
        % / DL-SCH
        if ~isempty(pdsch)
            
            pdsch.NTurboDecIts = 5;
            fprintf('PDSCH settings after DCI decoding:\n');
            disp(pdsch);

            % PDSCH demodulation and DL-SCH decoding to recover SIB bits.
            % The DCI message is now parsed to give the configuration of
            % the corresponding PDSCH carrying SIB1, the PDSCH is
            % demodulated and finally the received bits are DL-SCH decoded
            % to yield the SIB1 bits.

            fprintf('Decoding SIB1...\n\n');        
            % Get PDSCH indices
            [pdschIndices,pdschIndicesInfo] = ltePDSCHIndices(enb, pdsch, pdsch.PRBSet);
            [pdschRx, pdschHest] = lteExtractResources(pdschIndices, rxsubframe, hest);
            % Decode PDSCH 
            [dlschBits,pdschSymbols] = ltePDSCHDecode(enb, pdsch, pdschRx, pdschHest, nest);
            % Decode DL-SCH with soft buffer input/output for HARQ combining
            if ~isempty(decState)
                fprintf('Recombining with previous transmission.\n\n');
            end        
            [sib1, crc, decState] = lteDLSCHDecode(enb, pdsch, trblklen, dlschBits, decState);

            % Compute PDSCH EVM
            recoded = lteDLSCH(enb, pdsch, pdschIndicesInfo.G, sib1);
            remod = ltePDSCH(enb, pdsch, recoded);
            [~,refSymbols] = ltePDSCHDecode(enb, pdsch, remod);
            [rmsevm,peakevm] = pdschEVM(refSymbols{1}, pdschSymbols{1});
            fprintf('PDSCH RMS EVM: %0.3f%%\n',rmsevm);
            fprintf('PDSCH Peak EVM: %0.3f%%\n\n',peakevm);

            fprintf('SIB1 CRC: %d\n',crc);
            if crc == 0
                fprintf('Successful SIB1 recovery.\n\n');
            else
                fprintf('SIB1 decoding failed.\n\n');
            end
            
        else
            % Indicate that creating a PDSCH configuration from the DCI
            % message failed
            fprintf('Creating PDSCH configuration from DCI message failed.\n\n');
        end
        
    end
    if (numel(alldci)==0)
        % Indicate that DCI decoding failed 
        fprintf('DCI decoding failed.\n\n');
    end
    
    % Update channel estimate plot 
    figure(channelFigure);
    surf(abs(hest(:,:,1,1)));
    hSIB1RecoveryExamplePlots(channelFigure);
    channelFigure.CurrentAxes.XLim = [0 size(hest,2)+1];
    channelFigure.CurrentAxes.YLim = [0 size(hest,1)+1];   
    
    % Skip 2 frames and try SIB1 decoding again, or terminate if we
    % have less than 2 frames left. 
    if (size(rxgrid,2)>=(L*20))
        rxgrid(:,1:(L*20),:) = [];   % Remove 2 more frames
    else
        rxgrid = []; % Less than 2 frames left
    end
    enb.NFrame = mod(enb.NFrame + 2,1024);
        
end

%% Appendix
% This example uses the following helper functions:
%
% * <matlab:edit('hPDSCHConfiguration.m') hPDSCHConfiguration.m>
% * <matlab:edit('hSIB1RecoveryExamplePlots.m') hSIB1RecoveryExamplePlots.m>
