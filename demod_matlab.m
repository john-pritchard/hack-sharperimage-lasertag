clear 
close all

bias = 0.84;                % empirically determined bias voltage
lim = 0.6;                  % empirically determined limit to determine rise/fall edge
onpulse_start_lim = 5.5;    % ir message starts with a ~6ms pos-pulse
offpulse_end_lim = 4;       % when the message completes, there is a ~4.5ms off-period before the next message begins

% unzip the csv file
zipfilename = 'RigolDS1.zip';
csvfilename = 'RigolDS1.csv';
if ~isfile(csvfilename)
  unzip(zipfilename);
end

% load csv file, time-shift it to zero, and get the average sampling freq
tab = readtable(csvfilename);
t_bias = tab.Time_s_(1);
t = tab.Time_s_ - t_bias;
fs = 1/mean(diff(t));

% get the differential measurement (Vled), remove the bias, then digitize it
ir_raw = tab.MATH1_V_ - bias;
ir_dig = ir_raw > lim;


% -------------------------------------------------------------------------
% This is basically an inefficient low-pass filter, remove the 38kHz waveform
% -------------------------------------------------------------------------
tic;

% define digital states
HIGH = 1;
LOW = 0;
state = LOW;
tracking = false;

% track the indices of detected edges
% | (1) pos-edge | (2) neg-edge | (3) edge-edge duration | (4) 0=ON, 1=OFF
track_idx = [0 0 0 0];  % temporary indices array
on_idx = [];            % on-pulses indices array, appended by track_idx

% define a "timer" of sorts (in samples) that resets every time a 38kHz
% pulse is felt. When a sufficient gap is detected (track_limit), we know
% the low-freq pulse has ended.
track_samples = 0;
track_limit = ceil((1/38e3) * fs);  % 38khz period in samples

% run through the digitized (binary) signal and get the low-freq edges
for i = 2:length(ir_dig)
    % check if this is a pos/neg edge
    pos_edge = (ir_dig(i) - ir_dig(i-1)) > 0;
    neg_edge = (ir_dig(i) - ir_dig(i-1)) < 0;

    % update state if edge found.
    if pos_edge
        state = HIGH;
        track_samples = 0;      % pos edge resets counter
        if ~tracking            
            tracking = true;
            track_idx(1) = i;   % store the "start" edge 
        end
    elseif neg_edge
        state = LOW;
        track_idx(2) = i;       % store/update the "stop" edge
        track_idx(3) = track_idx(2) - track_idx(1);
        track_idx(4) = 1;
    end
    
    % increment counter while tracking, raise limit flag if in excess
    if tracking
        track_samples = track_samples + 1;
        if state == LOW && track_samples > track_limit               
            tracking = false;            
            if track_idx(3) > 2000
                on_idx(end+1,:) = track_idx;
            end
        end
    end
end

% recreate signal with new on/off times
ir_filtered = zeros(1, length(ir_dig));
for i = 1:height(on_idx)
    ir_filtered(on_idx(i, 1):on_idx(i, 2)) = on_idx(i, 4);
end
toc;
% -------------------------------------------------------------------------


% get the off-times, which are just the gaps between the on-times
off_idx = [];
for i = 1:height(on_idx)-1
    off_idx(end+1, 1) = on_idx(i, 2) + 1;
    off_idx(end, 2) = on_idx(i+1, 1) - 1;
    off_idx(end, 3) = off_idx(end, 2) - off_idx(end, 1);
    off_idx(end, 4) = 0;
end

% interweave on/off times into sequence
pulse_idx = [];
counter = 1;
for i = 1:min(height(on_idx), height(off_idx))
    pulse_idx(end+1,:) = on_idx(i,:);
    pulse_idx(end+1,:) = off_idx(i,:);
end

% convert the pulse widths in to milliseconds
pulse_idx(:,3) = pulse_idx(:,3)/fs*1e3;

% split the sequence into repeated messages
msg_start_idx = find(pulse_idx(:,3) > onpulse_start_lim & pulse_idx(:,4) > 0);
msg_end_idx = find(pulse_idx(:,3) > offpulse_end_lim & pulse_idx(:,4) == 0);
for i = 1:min(length(msg_start_idx), length(msg_end_idx))
    msgs{i} = pulse_idx(msg_start_idx(i):msg_end_idx(i),:);
end
disp(msgs)

% For convenience, let's overlay start/stop calculations on the raw signal
figure; plot(t, ir_raw); 
hold on;
for i = 1:height(on_idx)
    start_idx = on_idx(i, 1);
    stop_idx = on_idx(i, 2);
    plot(t(start_idx), ir_raw(start_idx), 'go', 'MarkerFaceColor', 'g');
    plot(t(stop_idx), ir_raw(stop_idx), 'ro', 'MarkerFaceColor', 'r');
end
hold off;