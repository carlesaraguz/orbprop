function [cds, items] = orblearnLoad3(path_to_props, d_max, max_files, sort_method = "reverse")
% ORBLEARNLOAD3 loads all propagation data (*.prop files) from the specified directory and
%   calculates the cross-distance vectors. Instead of generating a matrix of 1xN for each pair of
%   satellites (as in the original orblearnLoad), this function generates a matrix of 2xK, where K
%   is the number of samples in which the distance is considered an encounter. Thus, the amount of
%   information (i.e. the amount of columns) is significantly reduced. Consequently, it is necessary
%   to store the actual time for each of the cross-distance points: that's what the first column
%   d(:,1) is used for.
%
% Args:   path_to_props -> The path to a folder containing *.prop files.
%                 d_max -> Maximum distance to consider an encounter.
%             max_files -> Limit the amount of scanned files.
%           sort_method -> Whether to sort propagation files randomly ("rand"), backwards
%                          ("reverse" = default) or forwards ("normal").
%
% Usage:  [cds, items] = orblearnLoad("path/to/propagations/folder/", 1000)
%   where           cds ->  A Cross-Distance Struct, which has 2 children:
%                               cds.d       ->  A Kx2 matrix where K is the number of points in
%                                               which the cross-distance is less or equal to `d_max`.
%                               cds.p       ->  The pair of satellites that generate this cross-
%                                               distance.
%                               cds.tstart  ->  Start time of the propagation.
%                               cds.tend    ->  End time of the propagation.
%                               cds.tstep   ->  The sampling rate for this propagation.
%                 items ->  The total number of cross-distances C(x,2) where x is either `max_files`
%                           or the total number of *.prop files.
%

    search_path = strcat(path_to_props, "*.prop");
    csvfiles = dir(search_path);                    % Find all propagation files in this folder.
    if strcmp(sort_method, "rand")
        % Randomize the order of '*.prop' files:
        csvfiles = csvfiles(randperm(numel(csvfiles)));
    elseif strcmp(sort_method, "reverse")
        % Reverse the order of files:
        csvfiles = csvfiles(end:-1:1);
    elseif !strcmp(sort_method, "normal")
        printf("[    !] \x1b[31;1mError: unrecognized sorting type. Using \"normal\"\x1b[0m\n");
        fflush(stdout);
    end
    d_done = eye(numel(csvfiles));                  % Identity matrix with boolean 'done' flags.

    iterator_max = min(numel(csvfiles), max_files);
    if nchoosek(iterator_max, 2) > 500
        printf("[    !] \x1b[33mWarning: more than 500 cross-distances will be computed. Press a key to continue.\x1b[0m\n");
        pause;
    end
    printf("[    #] \x1b[33mInfo: will generate %d cross-distances\x1b[0m\n", nchoosek(iterator_max, 2));

    counter = 1;                            % Cross-distance pair counter.
    if numel(csvfiles) >= 2
        for ii = 1:iterator_max
            id_ii = str2num(strsplit(csvfiles(ii).name, "."){1});
            prop_ii = csvread(strcat(path_to_props, csvfiles(ii).name))(7:end, 2:5);  % Load data.
            for jj = 1:iterator_max
                if d_done(ii, jj) == 0
                    id_jj = str2num(strsplit(csvfiles(jj).name, "."){1});
                    printf("[%5d] Generating cross-distance for %5u and %5u: ", counter, id_ii, id_jj);
                    prop_jj = csvread(strcat(path_to_props, csvfiles(jj).name))(7:end, 2:5);  % Load data.

                    % Check that times are consistent:
                    c = sum(prop_ii(:, 1) != prop_jj(:, 1));
                    if c > 0 || prop_ii(1, 1) != prop_jj(1, 1) || prop_ii(end, 1) != prop_jj(end, 1)
                        printf("\x1b[31;1mError found in propagations: time vector does not match\x1b[0m\n");
                        d_k = zeros(1, 2);
                    else
                        % Calculate the cross-distance and shrink vector:
                        d_k = [prop_ii(:, 1) sqrt(sum((prop_jj(:, 2:4) - prop_ii(:, 2:4)).^2, 2))];

                        % The following pice of program does the same than:
                        %       d_idx = find(d_k(:, 2) <= d_max);
                        %       d_k = d_k(d_idx, :);
                        % But it preserves adjacent points (those that cross at d_max).

                        %   bflag:  TRUE when d(kk-1, 2) > d_max.
                        %   d_idx:  The indexes of d_k that will be kept.
                        bflag = 0;              % Initializes flag.
                        d_idx = 1;              % Initializes with the starting point.
                        % Traverse d_k looking for indexes that have to be kept:
                        for kk = 1:length(d_k)
                            if d_k(kk, 2) <= d_max              % This sample has to be kept:
                                if bflag && size(d_idx, 2) == 0 % The prev. sample wasn't kept.
                                    d_idx = [d_idx (kk - 1)];   % -- Save prev. sample (= d_max).
                                elseif bflag && d_idx(end) != (kk - 1)  % Idem.
                                    d_idx = [d_idx (kk - 1)];   % -- Save prev. sample (= d_max).
                                end
                                bflag = 0;                      % -- Clear the flag.
                                d_idx = [d_idx kk];             % -- Save the current sample.
                            else                                % This sample MIGHT not be kept:
                                d_k(kk, 2) = d_max;             % -- Overwrite with maximum value.
                                if !bflag                       % -- This sample has to be kept.
                                    d_idx = [d_idx kk];         % -- Save this sample.
                                    bflag = 1;                  % -- Flag up.
                                end                             % -- Else: the sample is NOT kept.
                            end
                        end
                        if d_idx(end) != length(d_k)
                            d_idx = [d_idx length(d_k)];        % Adds the last point.
                        end
                        d_k = d_k(d_idx, :);                    % Applies selection.

                        if size(d_k, 1) == size(prop_ii, 1)
                            printf("\x1b[32m%5d pp (%.0f%%)\x1b[0m\n", size(d_k, 1), 100 * size(d_k, 1) / size(prop_ii, 1));
                        elseif size(d_k, 1) > 0
                            printf("\x1b[35m%5d pp (%.0f%%)\x1b[0m\n", size(d_k, 1), 100 * size(d_k, 1) / size(prop_ii, 1));
                        else
                            printf("\x1b[33m%5d pp (%.0f%%)\x1b[0m\n", size(d_k, 1), 100 * size(d_k, 1) / size(prop_ii, 1));
                        end
                    end
                    fflush(stdout);

                    % Flag this pair of satellites as "done".
                    d_done(ii, jj) = 1;
                    d_done(jj, ii) = 1;

                    % If the vector is not empty, save it:
                    cds(counter).d = d_k;
                    cds(counter).p = [id_ii id_jj];
                    cds(counter).tstart = csvread(strcat(path_to_props, csvfiles(jj).name))(2, 2);
                    cds(counter).tend   = csvread(strcat(path_to_props, csvfiles(jj).name))(3, 2);
                    cds(counter).tstep  = csvread(strcat(path_to_props, csvfiles(jj).name))(4, 2);
                    ++counter;
                end
            end
        end
        printf("Done.\n");
        items = counter - 1;
    else
        printf("Unable to calculate distances with less than 2 propagation files.\n");
        cds = 0;
        items = 0;
    end
end
