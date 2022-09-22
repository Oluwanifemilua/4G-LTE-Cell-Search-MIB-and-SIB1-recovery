%hPDSCHConfiguration PDSCH configuration from P-/RA-/SI-RNTI masked DCI messages
%   [PDSCH,TRBLKLEN] = hPDSCHConfiguration(ENB,DCI,RNTI) 
%   decodes the physical downlink shared channel configuration PDSCH and
%   transport block length TRBLKLEN from received downlink control
%   information message DCI, eNodeB configuration ENB and radio network
%   temporary identifier RNTI. This function supports P-/RA-/SI-RNTI masked
%   DCI messages with DCI format 1A or 1C.

%   Copyright 2010-2016 The MathWorks, Inc.


function [pdsch,trblklen] = hPDSCHConfiguration(enb,dci,RNTI)

    pdsch = [];
    trblklen = 0;

    if (~any(strcmpi(dci.DCIFormat,{'Format1A','Format1C'})))
        return;
    end
    
    % For DCI Format 1A, NDLRB>=50 and distributed resource allocation, 
    % TS36.212 Section 5.3.3.1.3 indicates that:
    % "the new data indicator bit indicates the gap value"
    if (strcmp(dci.DCIFormat,'Format1A')==1) 
        if (enb.NDLRB>=50 && dci.AllocationType==1)
            dci.Allocation.Gap = dci.NewData;
        end
    end
        
    % Set general PDSCH parameters
    pdsch.RNTI = RNTI;
    pdsch.PRBSet = lteDCIResourceAllocation(enb, dci);
    pdsch.NLayers = enb.CellRefP;   
    pdsch.CSI = 'On';

    % Set DCI format specific parameters
    if (strcmp(dci.DCIFormat,'Format1A')==1)      
        % Calculate the transport block size
        tbsIndication = mod(dci.TPCPUCCH,2);
        if (tbsIndication)
            NPRB1A = 3;
        else
            NPRB1A = 2;
        end
        imcs = dci.ModCoding;
        itbs = imcs;
        trblklen = lteTBS(NPRB1A, itbs);
        
        % Set PDSCH parameters
        pdsch.Modulation = {'QPSK'};
        pdsch.RV = dci.RV;
    end
    
    if (strcmp(dci.DCIFormat, 'Format1C')==1)  
        % Set PDSCH RV parameter
        if (pdsch.RNTI==65535)
            % Set the PDSCH RV as per TS36.321 Section 5.3.1 if a System
            % Information message type (RNTI==0xFFFF). In this case assume
            % SystemInformationBlockType1 message.
            k = mod(floor(enb.NFrame/2), 4);
            RVK = mod(ceil(3/2*k), 4);
            pdsch.RV = RVK;
        else
            pdsch.RV = 0;            
        end
        
        % Set PDSCH modulation
        pdsch.Modulation = {'QPSK'};
        
        % Calculate the transport block size
        imcs = dci.ModCoding;
        itbs = imcs;
        trblklen = TBS1C(itbs);
    end             
    
    if (enb.CellRefP==1)
        pdsch.TxScheme = 'Port0';
    else
        pdsch.TxScheme = 'TxDiversity';
    end               

end

%TBS1C Transport block size from index
%   TBS = TBS1C(ITBS) is the transport block size from transport block size
%   index ITBS for the case of DCI Format 1C.

%   Copyright 2013-2014 The MathWorks, Inc.

function tbs = TBS1C(itbs)

    tbss = [40 56 72 120 136 144 176 208 224 256 280 296 328 336 392 ...
        488 552 600 632 696 776 840 904 1000 1064 1128 1224 1288 1384 ...
        1480 1608 1736];

    tbs = tbss(itbs+1);

end
