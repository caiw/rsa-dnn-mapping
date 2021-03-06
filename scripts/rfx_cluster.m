% RFX stats computed by flipping the sign of subjects R-maps randomly.
%
% Method published in Su et al. (2012) Int. Workshop on Pattern Recognition in NeuroImaging.  
%
% Original author: Li Su 2012-02
% Updated: Cai Wingfield 2015-11, 2016-03
function [observed_map_paths, corrected_ps] = rfx_cluster(map_paths, n_flips, stat, cluster_forming_threshold, fdr_threshold, userOptions)

    import rsa.*
    import rsa.meg.*
    import rsa.stat.*
    import rsa.util.*
    
    maps_dir = fullfile(userOptions.rootPath, 'Maps');
    simulation_dir = fullfile(userOptions.rootPath, 'Sim');

    n_subjects = numel(userOptions.subjectNames);
    
    
    %% Get actual data
    
    % Load the first dataset to look at size of data
    for chi = 'LR'
        hemi_mesh_stc.(chi) = mne_read_stc_file1(map_paths(1).(chi));
        [n_verts.(chi), n_timepoints] = size(hemi_mesh_stc.(chi).data);
        % delete data fields from hemi_mesh_stc to avoid broadcasting it to all
        % workers
        hemi_mesh_stc.(chi) = rmfield(hemi_mesh_stc.(chi), 'data');
    end
    n_verts_overall = n_verts.L + n_verts.R;
    
    % Compute an adjacency matrix of the downsampled mesh.
    vertex_adjacency = calculateMeshAdjacency(userOptions.targetResolution, userOptions.minDist, userOptions);
    for chi = 'LR'
        % 'iwm' - index within mask
        adjacency_matrix_iwm.(chi) = neighbours2adjacency(hemi_mesh_stc.(chi).vertices, vertex_adjacency);
    end
    
    % Load in and stack up subject correlation-maps
    all_subject_rhos = nan(n_subjects, n_verts_overall, n_timepoints);
    for subject_i = 1:n_subjects
        % Left
        hemi_mesh_stc.L = mne_read_stc_file1(map_paths(subject_i).L);
        all_subject_rhos(subject_i, 1:n_verts.L,       :) = hemi_mesh_stc.L.data;
        % Right
        hemi_mesh_stc.R = mne_read_stc_file1(map_paths(subject_i).R);
        all_subject_rhos(subject_i,   n_verts.L+1:end, :) = hemi_mesh_stc.R.data;
    end
    
    
    %% Simulation    
    
    % We will compute the maximum t-value for each
    % permutation and store those in a null distribution.
    
    % preallocate null distribution vectors for each hemisphere
    h0_l = nan(n_flips, 1);
    h0_r = nan(n_flips, 1);
    
    parfor flip_i = 1:n_flips
        
        % Occasional update
        if mod(flip_i, floor(n_flips/100)) == 0, prints('Flipping coin %d of %d...', flip_i, n_flips); end%if
        
        % Flip a coin for each subject
        flips = (2 * coinToss([n_subjects, 1, 1])) - 1;
        % Copy this to make it the same size as the data
        flips = repmat(flips, [1, n_verts_overall, n_timepoints]);
        
        % Apply the flips to the subject data.
        flipped_rhos = all_subject_rhos .* flips;
        
        if strcmpi(stat, 't')
            % Compute t-stats for this flip
            [h,p,ci, flipped_stats] = ttest(flipped_rhos);

            group_map_sim_both_hemis = squeeze(flipped_stats.tstat);
        elseif strcmpi(stat, 'r')
            % Compute average r-map
            group_map_sim_both_hemis = mean(flipped_rhos, 1);
            group_map_sim_both_hemis = squeeze(group_map_sim_both_hemis);
        else
            error('Must be ''t'' or ''r''.');
        end

        group_map_sim_L = group_map_sim_both_hemis(1:n_verts.L,       :);
        group_map_sim_R = group_map_sim_both_hemis(  n_verts.L+1:end, :);
        
        % For some reason Matlab won't let me do this loop inside of a
        % parfor.
        
        chi = 'L';
        
        [labelled_sim_clusters, vertex_level_threshold] = identify_spatiotemporal_clusters( ...
            adjacency_matrix_iwm.(chi), ...
            group_map_sim_L, ...
            cluster_forming_threshold);
        
        sim_cluster_stats = calculate_cluster_stats( ...
            labelled_sim_clusters, ...
            group_map_sim_L, ...
            vertex_level_threshold);
        
        h0_l(flip_i) = max(sim_cluster_stats);
        
        chi = 'R';
        
        [labelled_sim_clusters, vertex_level_threshold] = identify_spatiotemporal_clusters( ...
            adjacency_matrix_iwm.(chi), ...
            group_map_sim_R, ...
            cluster_forming_threshold);
        
        sim_cluster_stats = calculate_cluster_stats( ...
            labelled_sim_clusters, ...
            group_map_sim_R, ...
            vertex_level_threshold);
        
        h0_r(flip_i) = max(sim_cluster_stats);
    end
    
    h0.L = sort(h0_l); clear h0_l;
    h0.R = sort(h0_r); clear h0_r;
    
    
    %% Observed maps

    if strcmpi(stat, 't')
        [h,p,ci,stats] = ttest(all_subject_rhos);
        group_map_observed_overall = squeeze(stats.tstat);
    elseif strcmpi(stat, 'r')
        group_map_observed_overall = mean(all_subject_rhos, 1);
        group_map_observed_overall = squeeze(group_map_observed_overall);
        else
            error('Must be ''t'' or ''r''.');
    end
    
    % Set nan values to 0
    % TODO: why would there be nans?
    group_map_observed_overall(isnan(group_map_observed_overall)) = 0;
    
    % Split into hemispheres
    group_maps_observed.L = group_map_observed_overall(1:n_verts.L,       :);
    group_maps_observed.R = group_map_observed_overall(  n_verts.L+1:end, :);
    
    
    %% Identify observed clusters
    
    for chi = 'LR'
        
        [labelled_spatiotemporal_clusters.(chi), vertex_level_threshold] = identify_spatiotemporal_clusters( ...
            adjacency_matrix_iwm.(chi), ...
            group_maps_observed.(chi), ...
            cluster_forming_threshold);
        
        cluster_stats.(chi) = calculate_cluster_stats( ...
            labelled_spatiotemporal_clusters.(chi), ...
            group_maps_observed.(chi), ...
            vertex_level_threshold);
        
        % write out unthresholded map
        observed_map_paths.(chi) = fullfile( ...
            maps_dir, ...
            sprintf('%s_group_%s-map_observed-%sh.stc', userOptions.analysisName, stat, lower(chi)));
        write_stc_file( ...
            hemi_mesh_stc.(chi), ...
            group_maps_observed.(chi), ...
            observed_map_paths.(chi));
        
        % write out cluster map
        cluster_labels_map_paths.(chi) = fullfile( ...
            maps_dir, ...
            sprintf('%s_group_%s-map_labelled_clusters-%sh.stc', userOptions.analysisName, stat, lower(chi)));
        write_stc_file( ...
            hemi_mesh_stc.(chi), ...
            labelled_spatiotemporal_clusters.(chi), ...
            cluster_labels_map_paths.(chi));
    
    
        %% Squash clusters that don't meet the corrected significance level.
        
        cluster_ids = unique(labelled_spatiotemporal_clusters.(chi));
        % The cluster whose id is zero is not a cluster at all, so we delete it
        % here. It's the background!
        cluster_ids = cluster_ids(cluster_ids > 0);
        
        % Copy into binary map
        corrected_clusters.(chi) = double(labelled_spatiotemporal_clusters.(chi) > 0);
        
        corrected_ps.(chi) = nan(size(cluster_ids));
        
        for cluster_i = cluster_ids'
            
            % Work out quantile position of actual value in h0 (which is
            % sorted) and assign that as a corrected p.
            corrected_ps.(chi)(cluster_i) = 1 - ((sum(h0.(chi) < cluster_stats.(chi)(cluster_i)) + 0.5*sum(h0.(chi) == cluster_stats.(chi)(cluster_i)))/numel(h0.(chi)));
            
            % Delete this cluster if it doesn't meet the corrected threshold
            if corrected_ps.(chi)(cluster_i) > fdr_threshold
                corrected_clusters.(chi)(labelled_spatiotemporal_clusters.(chi) == cluster_i) = 0;
            end
        end
        
        % Make it zeros and ones.
        
        % write out corrected cluster map
        observed_thresholded_map_paths_corr.(chi) = fullfile( ...
            maps_dir, ...
            sprintf('%s_group_%s-map_observed_thresholded_corrected-%sh.stc', userOptions.analysisName, stat, lower(chi)));
        write_stc_file( ...
            hemi_mesh_stc.(chi), ...
            corrected_clusters.(chi), ...
            observed_thresholded_map_paths_corr.(chi));
    
    end

end%function

function cluster_stats = calculate_cluster_stats(labelled_spatiotemporal_clusters, group_maps, vertex_level_threshold)

...%cluster_stats = cluster_peak( ...
...%cluster_stats = cluster_extent( ...
cluster_stats = cluster_exceedence_mass( ...
            labelled_spatiotemporal_clusters, ...
            group_maps, ...
            vertex_level_threshold);

end
