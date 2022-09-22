%hPlotPositions returns plot sizes and positions based on screen resolution
%   [REPOSITIONPLOTS,POSITION] = hPlotPositions() determines whether plot
%   tiling can be supported based upon the user's display resolution. If
%   plot tiling can be supported, REPOSITIONPLOTS is returned as true and
%   POSITION contains an array of vectors of the form [left bottom width
%   height] indicating the X-Y position and size for each plot. The plots
%   are arranged in a 3x2 tiled arrangement. If plot tiling cannot be
%   supported, REPOSITIONPLOTS is returned as false and POSITION is not
%   valid.
%
%   The plots are arranged in the following manner:
%    3x2 Tile
%            Plot 5    Plot 1    Plot 2
%            Plot 6    Plot 3    Plot 4

%   Copyright 2017 The MathWorks, Inc.

function [repositionPlots,position] = hPlotPositions()

    su=get(0,'Units');
    set(0,'Units','pixels');
    res = get(0,'ScreenSize');
    set(0,'Units',su);

    if ismac
        minres = 1440;
    else % ispc,isunix
        minres = 1280;
    end
    
    if (res(3)>minres) 
        xpos = fix(res(3)*[1/2; 3/4; 1/2; 3/4; 1/4; 1/4]);
        ypos = fix(res(4)*[1/2; 1/2; 1/16; 1/16; 1/2; 1/16]);
        xsize = (xpos(2) - xpos(1) - 20)*[1; 1; 1; 1; 1; 1];   
        ysize = fix(xsize(1) * 5 / 6)*[1; 1; 1; 1; 1; 1];
        position = [xpos ypos xsize ysize];
        
        repositionPlots = true;
    else
        position = zeros(6,4);
        
        repositionPlots = false;
    end
        
end
