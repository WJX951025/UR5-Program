clear global; clear; 
global LLR_memory






joint = [1 2 3 4];                                % index of joint(s) to be controlled
% joint 1 = base angle
% joint 2 = aluminum arm angle
% joint 3 = plastic arm angle
                                                % (1 = base, 2 = shoulder, etc.)
                                                % can be a vector too
n = length(joint);                              % number of joints to be controlled
joint = joint(:)+(0:6:6*(n-1))';                % convert into sequential index
joint_select = zeros(6,n);                      % prepare zeros
joint_select(joint) = 1;                        % assing 1 at the right places

if nargin < 1, Port = 'COM1'; end;              % default port
if nargin < 2, ref = 0; end;                    % default reference
if nargin < 3, Kp = 3; end;                     % default control gain

h = 0.05;                                       % sampling period
eps = 0.05;                                     % tolerance around ref
umax = 0.7;                                     % maximum allowed control 

xx = zeros(2,7);                                % aux var for BE conversion

% initialize, open the port, define timer
hwinit;                                         % read HW parameters
daoutgain = daoutgain(1:6);                     % ignore laser
daoutoffs = daoutoffs(1:6);                     % ignore laser
com = rs232('GetParams','default');             % get default RS232 parameters
com.Port = 'COM1';                                % define port number
com.BaudRate = 115200;                          % define Baud rate
com.ReadTimeout = 1;                            % define short timeout
com.WriteTimeout = 1;                           % define short timeout
[params,result]=rs232('open',com);              % open the port


% load memorybackup
load referencemodel;  % you can create a reference model by demonstrate.m
load weights;
load processmemory;

%% initialize memory
lxr    = 6;         % size of input of reference model
lyr    = 6;         % size of output of reference model
mpr    = 1;         % pointer to reference memory
flagr  = 0;         % do not learn
kr     = 15;        % number of nearest neighbours used in local regression
% sizeR = 500;
LLR_memory{1,mpr} = [Ref(1:6,:) ; W*Ref(7:end,:) ; zeros(1,length(Ref))];   % load the reference samples in memory
% detailed description:
% LLR_memory=[x1(k) x2(k) x3(k) xd1(k) xd2(k) xd3(k) | W*(x1(k+1) x2(k+1)
% x3(k+1) xd1(k+1) xd2(k+1) xd3(k+1) | param1 ]

figure(1)
realtimeplot=subplot(2,2,2);
%clf;
%newplot;
title('Reference Vector Field');
% 3D plot of reference vector fields:
line([Ref(1,:);Ref(1,:)+Ref(4,:)],[Ref(2,:);Ref(2,:)+Ref(5,:)],[Ref(3,:);Ref(3,:)+Ref(6,:)],'Color','k');
hold on;
drawnow





lxp    = 15;        % size of input of reference model
lyp    = 3;         % size of output of reference model
mpp    = 2;         % pointer to reference memory
flagp1 = 0;         % do not learn
flagp2 = 1;         % learn 
kp     = 40;        % number of nearest neighbours used in local regression
sizeP  = 1000; 
LLR_memory{1,mpp} = [randn(lxp,sizeP) ; 0.1*randn(lyp,sizeP) ; zeros(1,sizeP)]; % empty processmemory
LLR_memory{1,mpp} = processmemory;  % load the previous processmemory


learnedplot=subplot(2,2,4);
%newplot;
title('Learned Vector Field');
LRef=LLR_memory{1,mpp};
plot3(LRef(1,:),LRef(2,:),LRef(3,:),'.');
view(3);
camproj perspective;
pbaspect([1 1 1]);
drawnow



%% initialize states and stuff
rs232('write',com,uint8(128));                       % control byte for read D/A
xx(:)   = rs232('read',com,14);                        % read 14 bytes from 7 sensors
x       = double(xx'*[256 1]');                            % convert to big endian
x       = adingain(:).*(x + adinoffs(:));                  % scale to physical range
x       = joint_select'*x(1:6);                            % select the right variable 
input   = [x(1:3) ;zeros(3,1)];
u       = zeros(3,1);

% display state   
subplot(2,2,2);
currentstatepoint=plot3([x(1)],[x(2)],[x(3)],'or');
view(3);
camproj perspective;
pbaspect([1 1 1]);
    
 subplot(2,2,3);
 newplot
 [ZZ,HH]=CreateRobot;


for i = 1:2000
    t = clock;
%% Read state
    inputprev = input;
    uprev = u(1:3);
    rs232('write',com,uint8(128));                       % control byte for read D/A
    xx(:) = rs232('read',com,14);                        % read 14 bytes from 7 sensors
    x = double(xx'*[256 1]');                            % convert to big endian
    x = adingain(:).*(x + adinoffs(:));                  % scale to physical range
    x = joint_select'*x(1:6);                            % select the right variable  
    
 % display state   
    set(currentstatepoint,'xdata',x(1),'ydata',x(2),'zdata',x(3));
    axis(realtimeplot,[-1.6 1.6 -1.6 1.6 -1.6 1.6]);
    
 % display memory
    LRef=LLR_memory{1,mpp};
    subplot(2,2,4);
    plot(LRef(1,:),LRef(2,:),'.')
 
     DrawRobot(ZZ,HH,x(1),x(2),x(3),x(4));

%    subplot(2,2,3);
%    plot(LRef(1,:),LRef(3,:),'.')
    %line([LRef(1,:);LRef(1,:)+LRef(4,:)],[LRef(2,:);LRef(2,:)+LRef(5,:)],[LRef(3,:);LRef(3,:)+LRef(6,:)],'Color','b');
    %line([LRef(1,:);LRef(7,:)],[LRef(2,:);LRef(8,:)],[LRef(3,:);LRef(9,:)],'Color','b');
    
    %plot3(LRef(1,:),LRef(2,:),LRef(3,:),'.')
    %view(3);
    %camproj perspective;
    %pbaspect([1 1 1]);
    %drawnow
drawnow

    
    input  =[x(1:3) ; (x(1:3)-inputprev(1:3))];          % deterministic state description
%% Reference model
    [ref model ns NN]  = Locallinearmodel(input,kr,flagr,[],mpr,1);%[prediction model index memoryindex]
    u = Locallinearmodel([W*input;ref],kp,flagp1,[],mpp);    % dead beat control
    u = [u ; .4.*(-2*x(2)-x(3)-x(4))];
    u = min(umax,max(-umax,u));                          % saturate control action
    ud = joint_select*u;                                 % complete control vector
    ud = daoutgain(:).*ud + daoutoffs(:);                % scale to digital range
%% Send u to system
    rs232('write',com,uint8(0));                         % control byte for send all actuators
    rs232('write',com,uint8(ud)');                        % write 6 bytes to 6 actuators
%% Learn inverse process model
    Locallinearmodel([W*inputprev;W*input],kp,flagp2,uprev,mpp,0);
    reference(:,i) = ref;
    state(:,i)     = input;
    actuation(:,i) = u(1:3);
    while all(clock-t < h-0.1*h), end;                   % wait for the next sample


end


processmemory=LLR_memory{1,mpp};
save processmemory processmemory;  % remember processmemory for next imitation







%% reset actuators, close the port
rs232('write',com,uint8(56));                   % laser off
rs232('write',com,uint8(0));                    % control byte for send all actuators
rs232('write',com,uint8(127*ones(6,1)));        % reset all 6 actuators to 0 (127 bin)
rs232('close',com);                             % close serial port

figure(3);plot(reference(1,:)','r');title('reference');hold on;
plot((W(1,1)*state(1,:))','r*');title('states');
plot(reference(2,:)','b');title('reference');
plot((W(2,2)*state(2,:))','b*');title('states');
plot(reference(3,:)','k');title('reference');
plot((W(3,3)*state(3,:))','k*');title('states');
legend('base ref','base state','shoulder ref','shoulder state','elbow ref','elbow state')