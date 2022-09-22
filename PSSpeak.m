function p_peaks = PSSpeak(enb,waveform)

% Primary cell search.
corrcfg.PSS='On';
corrcfg.SSS='Off';
corrcfg.CellRS='Off';
ids= [0 1 2];
p_peaks=zeros(numel(ids),1);
for p=1:numel(ids)
    idx=p;
    enb.NCellID=ids(p);
    [~,corr]=lteDLFrameOffset(enb,waveform,corrcfg);
    % Record peak correlation value.
    p_peaks(idx)=max(corr(:));
end
p_peaks=max(p_peaks);

