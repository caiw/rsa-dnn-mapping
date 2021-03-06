function dRDM = triphone_dRDM(distance_type, frame_cap)

    if ~exist('distance_type', 'var'), distance_type = 'Correlation'; end
    
    triphone_data = load('/imaging/cw04/CSLB/Lexpro/Analysis_DNN/Models/actual_triphone_values.mat');
    triphone_data = orderfields(triphone_data);
    
    words = fieldnames(triphone_data);
    % CONDITIONS ARE IN ALPHABETICAL ORDER OF WORDS
    words = sort(words);
    n_words = numel(words);
    
    % This data starts from frame 2, so we must add an additional blank
    % frame to begin with.  This is just an aspect of using HTK's output.
    [n_timepoints_trimmed, n_triphones] = size(triphone_data.(words{1}));
    
    dRDM = struct();
    
    dRDM(1).RDM  = squareform(zeros(n_words, n_words));
    dRDM(1).Name = sprintf('triphone-%02d', 1);
    
    for t = 1:n_timepoints_trimmed
        
        % don't exceed the frame cap
        if t+1 > frame_cap, break; end
       
        data_this_frame = nan(n_words, n_triphones);
        for word_i = 1:n_words
            word = words{word_i};
            data_this_frame(word_i, :) = triphone_data.(word)(t, :);
        end
        
        dRDM(t+1).RDM = pdist(data_this_frame, distance_type);
        dRDM(t+1).Name = sprintf('triphone-%02d', t+1);
        
    end

end
