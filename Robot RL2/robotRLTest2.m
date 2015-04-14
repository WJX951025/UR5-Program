%robotRLTest2 is a script to test the RL-based additive compensator to 
% the UR5 robot. The learning process is done while following a straight 
% line trajectory. RL is an actor-critic with radial basis functions as 
% the approximator
% 
% Yudha Prawira Pane (c)
% created on      : Mar-23-2015
% last updated on : Apr-14-2015

%% Start ups and initialization
format long;
clc; close all;
clearvars -except arm UR5
loadParamsUR5_2;
load('wtrajMemoryfixed.mat');

if (~exist('arm','var'))
    clc; clear; close all;
    startup; 
    arm = URArm();
    IP_ADDRESS = '192.168.1.50';
    arm.fopen(IP_ADDRESS);   
    arm.update();
end
arm.moveJoints(params.qHome,1,2,2);
pause(2);

%% Trajectory and experiments-related variables
EXPERIMENT_TIME = 5;
SAMPLING_TIME   = params.ts;
N               = EXPERIMENT_TIME/SAMPLING_TIME; % number of samples 
time            = 0:SAMPLING_TIME:EXPERIMENT_TIME; 
time(end)       = [];

wrefTRAJ        = zeros(6,N);   % reference trajectory, will be populated in the iteration
qrefTRAJ        = zeros(6,N);   % joint space reference trajectory

%% Create the trajectory
arm.update();
initPos         = arm.getToolPositions();
q0              = arm.getJointsPositions();
initOrientation = initPos(4:end);

offset              = [-0.20 0 0 0 0 0]';
finalPos            = initPos + offset;
discretizedOffset   = offset/N;

for i = 1:N
    wrefTRAJ(:,i) = initPos + (i-1)*discretizedOffset; % populate reference trajectory
end

qrefTRAJ(:,1) = q0;

% Generate joint space trajectory 
for i = 1:N-1
    ds = wrefTRAJ(:,i+1) - wrefTRAJ(:,i);    

    % Calculate the joint space trajectory using inverse jacobian    
    J = UR5.jacob0(qrefTRAJ(:,i));
    dq = J\ds;
    qrefTRAJ(:,i+1) = qrefTRAJ(:,i) + dq;
end


%% Non-volatile memory
k               = 1;                        % initialize index variable
Phi(:,k)        = params.phi;               % actor parameters memory
Theta(:,k)      = params.theta;             % critic parameters memory
Ret(:,k)        = zeros(params.Ntrial,1);   % return memory
V(k)            = 0;                        % initialize value function
uSel(k)         = 1;                        % actor parameter update selector, 1 for update & 0 for not update
iterIndex(k)    = 1;                        % iteration indexing. Useful for animation purpose   
oldCounter      = 1;
qdotRef(:,k)    = zeros(6,1);               % the nominal reference velocity
u(k)            = 0;                        % action calculated by actor
qTable(:,k)     = zeros(6,1);               % joint position
wTable(:,k)   	= zeros(6,1);               % tool position
wdotTable(:,k)  = zeros(6,1);               % tool velocity
jointsVel(:,k) 	= zeros(6,1);               % joint velocity

%% Volatile memory
volDelta_u      = 0;
voluad          = 0;
volu            = 0;
volqdotRef      = zeros(6,1);
volqdotRefu     = zeros(6,1);
volqTable       = zeros(6,1);               % joint position
volwTable       = zeros(6,1);               % tool position
volwdotTable    = zeros(6,1);        % tool velocity

%% Misc variables
wdotPlot = linspace(params.zdotllim, params.zdotulim, size(wrefTRAJ,2));

%% Start learning trials
for counter = 1:params.Ntrial
    arm.moveJoints(qrefTRAJ(:,1),2,3,1); % move the robot to the first position of the qrefTRAJ safely
    pause(1);
    arm.update();        
    qTable(:,1)         = arm.getJointsPositions();    
    wTable(:,1)         = arm.getToolPositions();
    wdotTable(:,1)      = arm.getToolSpeeds();
        
    urand(1)    = 0;	% initialize input and exploration signal
    r(1)        = 0;	% initialize reward/cost
    e_c         = 0;
    
    if( mod(counter, 50) == 0)
        pause(0.1);
    end
%     TIMER = tic;
    for i=1:N-1
        if (counter > oldCounter)          
            oldCounter  = counter;
            iterIndex(k)= 1;      	% new trial detected, set to 1
        else
            iterIndex(k)= 0;     	% always set to zero unless new trial is detected           
        end

        %% Calculate RL-based additive compensator
        if mod(i,params.expSteps) == 0 	% explore only once every defined time steps
            urand(i)  = params.varRand*randn;                                      
        else
            urand(i)  = 0;
        end
        Delta_u             = urand(i);   

        u(i)                = actorUR5_2([wTable(3,i); wdotTable(3,i)], params); 
        [uad(i), uSel(i)]   = satUR5_2(u(i), params, Delta_u);  
%         Delta_u             = uad(i) - u(i);
        volDelta_u(i)       = Delta_u;

        %% Combine the nominal control input with the RL-based compensator
        qdotRef(:,i)        = (qrefTRAJ(:,i+1) - qrefTRAJ(:,i))/SAMPLING_TIME;
        qdotRefu(:,i)       = qdotRef(:,i) + [0; 0; uSel(i)*uad(i); 0; 0; 0];       
        
        %% Apply control input, measure state, receive reward        
        tic
        arm.setJointsSpeed(qdotRefu(:,i),params.acc,3*SAMPLING_TIME);

        while(toc<SAMPLING_TIME)
        end
        arm.update();  
        qTable(:,i+1)       = arm.getJointsPositions();    
        wTable(:,i+1)       = arm.getToolPositions();      
        wdotTable(:,i+1)    = arm.getToolSpeeds();
        if (wdotTable(3,i+1) > params.zdotulim)
            wdotTable(3,i+1)  = params.zdotulim;
        elseif (wdotTable(3,i+1) < params.zdotllim)
            wdotTable(3,i+1)  = params.zdotllim;
        end
        

%         abs(wTable(3,k+1)-wrefTRAJ(3,i+1))
%         if(rms(qTable(:,k+1)-qrefTRAJ(:,i+1))>0.002)
%             arm.setJointsSpeed(zeros(6,1), 0, 10);
%             pause(10);
%             error('robot deviates from trajectory!');     
%         end
        r(i+1)      = costUR5_2(wTable(3,i), wdotTable(3,i),  uSel(i)*uad(i), wrefTRAJ(3,i), params); 	% calculate the immediate cost 
        
        %% Compute temporal difference & eligibility trace
        V(i)        = criticUR5_2([wTable(3,i); wdotTable(3,i)], params);                    	% V(x(k))
        V(i+1)      = criticUR5_2([wTable(3,i+1); wdotTable(3,i+1)], params);                	% V(x(k+1))
        delta(i)    = r(i+1) + params.gamma*V(i+1) - V(i);                  % temporal difference 
        e_c         = params.gamma*params.lambda*e_c + rbfUR5_2([wTable(3,i); wdotTable(3,i)], params);

        %% Update critic and actor parameters
        % Update actor and critic
        params.theta	= params.theta + params.alpha_c*delta(i)*rbfUR5_2([wTable(3,i); wdotTable(3,i)], params);                 % critic
        params.phi      = params.phi + params.alpha_a*delta(i)*uSel(i)*rbfUR5_2([wTable(3,i); wdotTable(3,i)],params);   % actor 1 

        Phi(:,i+1)      = params.phi;    % save the parameters to memory
        Theta(:,i+1)    = params.theta;

        %% Compute return 
        Ret(counter,i+1)    = params.gamma*Ret(counter,i) + r(i+1);  % update return value

        %% Update time step and initial state
        k   = k+1;          % update index variable
    end
%     toc(TIMER)
    % Plotting purpose
    if mod(counter,params.plotSteps) == 0
        clf;
        figure(1); title(['Iteration: ' int2str(counter)]);
        subplot(321); 
        plotOut = plotrbfUR5_2(params, 'critic', params.plotopt); title(['\bf{CRITIC}  Iteration: ' int2str(counter)]); colorbar;
        xlabel('$z  \hspace{1mm}$ [mm]','Interpreter','Latex'); ylabel('$\dot{z}  \hspace{1mm}$ [mm]','Interpreter','Latex'); zlabel('$V(z)$ \hspace{1mm} [-]','Interpreter','Latex'); %colorbar 
        hold on; plot(wTable(3,:), wdotTable(3,:), 'r.');
        subplot(322); 
        plotOut = plotrbfUR5_2(params, 'actor', params.plotopt); title('\bf{ACTOR}');  colorbar;
        hold on; plot(wTable(3,:), wdotTable(3,:), 'r.'); 
        plot(wrefTRAJ(3,:),wdotPlot,'b');
        xlabel('$z  \hspace{1mm}$ [mm]','Interpreter','Latex'); ylabel('$\dot{z}  \hspace{1mm}$ [mm]','Interpreter','Latex'); zlabel('$\pi(z)$ \hspace{1mm} [-]','Interpreter','Latex'); %colorbar 
        subplot(323);
        plot(delta); title('\bf{Temporal difference}');% ylim([-10 5]);
        xlabel('time steps');
        subplot(324);
        plot(sum(Ret,2)); title('\bf{Return}'); %ylim([-10 5]);
        xlabel('trials');
        subplot(325); plot(time, 1000*wTable(3,:)); hold on; plot(time, 1000*wrefTRAJ(3,:), 'r'); plot(time,1000*wtrajMemory(3,:), 'g');
        xlabel('time (seconds)'); ylabel('Z position (mm)'); xlim([0 params.t_end]); title('reference (red), RL (blue), no-RL (green)');       
        subplot(326); plot(time(1:end-1), u, time(1:end-1), volDelta_u, 'r'); 
        xlabel('time (seconds)'); ylabel('additive input (rad/s)'); xlim([0 params.t_end]); title('Actor (b) & exploration (r)');       
        
        pause(0.5);           
    end
end    


pause(1);
arm.update();

%% Data Logging
err                     = arm.getToolPositions()-finalPos;
dataLOG.Name            = 'Robot Log Data';
dataLOG.Notes           = ['Created on: ' datestr(now) '   The robot was commanded using setJointsSpeed with constant offset'];
dataLOG.SamplingTime    = SAMPLING_TIME;
dataLOG.Time            = time;
dataLOG.refTRAJ         = wrefTRAJ;
dataLOG.wTable          = wTable;
dataLOG.qrefTRAJ        = qrefTRAJ;
dataLOG.qTable          = qTable; 
dataLOG.ErrorX          = wrefTRAJ(1,:)-wTable(1,:);
dataLOG.ErrorY          = wrefTRAJ(2,:)-wTable(2,:);
dataLOG.ErrorZ          = wrefTRAJ(3,:)-wTable(3,:);
dataLOG.rmsX            = rms(wrefTRAJ(1,:)-wTable(1,:));
dataLOG.rmsY            = rms(wrefTRAJ(2,:)-wTable(2,:));
dataLOG.rmsZ            = rms(wrefTRAJ(3,:)-wTable(3,:));
dataLOG.MaxAbsX         = max(abs(wrefTRAJ(1,:)-wTable(1,:)));
dataLOG.MaxAbsY         = max(abs(wrefTRAJ(2,:)-wTable(2,:)));
dataLOG.MaxAbsZ         = max(abs(wrefTRAJ(3,:)-wTable(3,:)));

%% Display trajectory and errors
figure; subplot(211);
plot(time(:), wrefTRAJ(1,:), time(:), wTable(1,:));
legend('reference traj', 'tool traj'); title('reference vs actual trajectory X-axis');
subplot(212);
plot(time(:), dataLOG.ErrorX);
title('trajectory error X-axis');

figure; subplot(211);
plot(time(:), wrefTRAJ(2,:), time(:), wTable(2,:));
legend('reference traj', 'tool traj'); title('reference vs actual trajectory Y-axis');
subplot(212);
plot(time(:), dataLOG.ErrorY);
title('trajectory error Y-axis');

figure; subplot(211);
plot(time(:), wrefTRAJ(3,:), time(:), wTable(3,:));
legend('reference traj', 'tool traj'); title('reference vs actual trajectory Z-axis');
subplot(212);
plot(time(:), dataLOG.ErrorZ);
title('trajectory error Z-axis');

%% Save data
savefolder = 'D:\Dropbox\TU Delft - MSc System & Control\Graduation Project (Thesis)\UR5 Robot\UR5 Programs\Robot Test\recorded data\';
save([savefolder 'dataLOG_' datestr(now,'dd-mmm-yyyy HH-MM-SS') '.mat'], 'dataLOG');