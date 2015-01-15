%GENERATETRAJ1 generate various trajectories
%
% the trajectories are set as workspace variables
% 
% Yudha Prawira Pane (c)
% Created on Jan-14-2015

qEnd1 = deg2rad([-5.16 -62.44 67.79 -5.21 84.83 180.01]);
qTraj1 = jtraj(qHome, qEnd1, 200); % generate trajectory with 100 steps
