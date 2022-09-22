% hSIB1RecoveryExamplePlots configure plots for SIB1RecoveryExample

% Copyright 2014-2017 The MathWorks, Inc.

function [spectrumAnalyzer,synchCorrPlot,pdcchConstDiagram] = hSIB1RecoveryExamplePlots(channelFigure,varargin)

    if (nargin==2)
        
        sr = varargin{1};
        
        % plot sizing and positioning
        [repositionPlots,plotPositions] = hPlotPositions();

        % Received signal spectrum
        spectrumAnalyzer = dsp.SpectrumAnalyzer();
        spectrumAnalyzer.Name = 'Received signal spectrum';
        spectrumAnalyzer.SampleRate = sr;
        spectrumAnalyzer.ReducePlotRate = false;
        spectrumAnalyzer.PlotMaxHoldTrace = true;
        spectrumAnalyzer.PlotMinHoldTrace = true;
        spectrumAnalyzer.ShowGrid = true;
        if (repositionPlots)
            spectrumAnalyzer.Position = plotPositions(1,:);
        end

        % PSS/SSS correlation 
        synchCorrPlot = dsp.ArrayPlot();
        synchCorrPlot.Name = 'PSS/SSS correlation';
        synchCorrPlot.XLabel = 'Timing offset (samples)';
        synchCorrPlot.YLabel = 'Correlation level';
        synchCorrPlot.PlotType = 'Line';
        synchCorrPlot.ShowGrid = true;
        if (repositionPlots)
            synchCorrPlot.Position = plotPositions(2,:);
        end

        % PDCCH constellation
        pdcchConstDiagram = comm.ConstellationDiagram();
        pdcchConstDiagram.Name = 'PDCCH constellation';
        pdcchConstDiagram.ShowReferenceConstellation = false;
        pdcchConstDiagram.ShowGrid = true;
        if (repositionPlots)
            pdcchConstDiagram.Position = plotPositions(3,:);
        end

        % Channel magnitude response
        channelFigure.Name = 'Channel magnitude response';
        channelFigure.NumberTitle = 'off';
        channelFigure.Color = [40 40 40]/255;   
        channelFigure.Visible = 'off';
        if (repositionPlots)
            channelFigure.Position = plotPositions(4,:);      
        end
        
    else
        
        figure(channelFigure);
        shading flat;
        channelFigure.CurrentAxes.XColor = [175 175 175]/255;
        channelFigure.CurrentAxes.YColor = [175 175 175]/255;
        channelFigure.CurrentAxes.ZColor = [175 175 175]/255;
        channelFigure.CurrentAxes.Color = [0 0 0];
        channelFigure.CurrentAxes.XGrid = 'on';
        channelFigure.CurrentAxes.YGrid = 'on';
        channelFigure.CurrentAxes.ZGrid = 'on';
        channelFigure.CurrentAxes.XLabel.String = 'OFDM symbols';
        channelFigure.CurrentAxes.XLabel.FontSize = 8;
        channelFigure.CurrentAxes.YLabel.String = 'Subcarriers';
        channelFigure.CurrentAxes.YLabel.FontSize = 8;
        channelFigure.CurrentAxes.ZLabel.String = 'Magnitude';
        channelFigure.CurrentAxes.ZLabel.FontSize = 8;
        channelFigure.CurrentAxes.View = [-30 60];
        
    end

end
