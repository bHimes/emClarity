function [vX, vY, vZ] = EMC_multi_vectorCoordinates(SIZE, METHOD, OPTIONAL)
% [vX, vY, vZ] = EMC_multi_vectorCoordinates(SIZE, METHOD, OPTIONAL)
% Compute gridVectors.
%
% SIZE (vector):                Size of the vectors to compute; [x, y, z] or [x, y]
%                              	Values correspond to a number of pixels, as such, it should be integers.
%
% METHOD (str):                 Device to use; 'gpu' or 'cpu'.
%
% OPTIONAL (cell | struct):     Optional parameters.
%                               If cell: {field,value ; ...}, note the ';' between parameters.
%                               NOTE: Can be empty.
%                               NOTE: Unknown fields will raise an error.
%
% -> 'shift' (vector):          [x, y, z] or [x, y] translations to apply (should correspond to SIZE)
%                               default = no shifts
%
% -> 'origin' (int):            Origin convention
%                               -1: zero frequency first (fft output)
%                               0: real origin (if even nb of pixel, the center is in between 2 pixels)
%                               1: right origin (extra pixel to the left; ceil((N+1)/2))
%                               2: left origin (extra pixel to the right)
%                               emClarity uses the right origin convention (ORIGIN=1).
%                               default = 1
%
% -> 'normalize' (bool):        Normalize the vectors between -0.5 and 0.5.
%                               default = false
%
% -> 'half' (bool):             Compute half of the X vectors (useful for rfft)
%                               default = false
%
% -> 'isotrope' (bool):         Stretch the vector values to the smallest dimensions.
%                               default = false
%
%--------
% TODO 1:                       Add an option (like flgHalf = -1) to compute only 1/4 (or 1/8 if 3d)
%                               of the grids/vectors. This could be useful for masks and filters that
%                               usually have a C4 symmetry. To regenerate the full grids, we can then
%                               have a function that takes this 1/4|8 grid and the ORIGIN/flgShiftOrigin,
%                               to compute the entire grid with the desired origin. It should be faster,
%                               specially for sphere/cylinder masks and filters where computing the taper
%                               can be expensive...
%
%--------
% EXAMPLE: [x,y,z] = EMC_multi_vectorCoordinates([10,9,8], 'gpu', {})
% EXAMPLE: [x, y]  = EMC_multi_vectorCoordinates([64,64], 'cpu', {'origin',-1 ; 'normalize',true})

%% checkIN
[flg3d, ndim] = EMC_is3d(SIZE);
validateattributes(SIZE, {'numeric'}, {'vector', 'numel', ndim, 'nonnegative', 'integer'}, '', 'SIZE');

if ~(strcmpi('gpu', METHOD) || strcmpi('cpu', METHOD))
    error("method should be 'cpu' or 'gpu', got %s", METHOD)
end

% Extract optional parameters
OPTIONAL = EMC_extract_optional(OPTIONAL, {'origin', 'shift', 'normalize', 'half', 'isotrope'});

if isfield(OPTIONAL, 'origin')
    if ~(OPTIONAL.origin == -1 || OPTIONAL.origin == 0 || OPTIONAL.origin == 1 || OPTIONAL.origin == 2)
        error("origin should be 0, 1, 2, or -1, got %d", OPTIONAL.origin)
    end
else
    OPTIONAL.origin = 1;  % default
end

if isfield(OPTIONAL, 'shift')
    validateattributes(OPTIONAL.shift, {'numeric'}, {'vector', 'numel', ndim, 'finite', 'nonnan'}, ...
                       '', 'shift');
else
    OPTIONAL.shift = zeros(1, ndim);  % default
end

if isfield(OPTIONAL, 'normalize')
    if ~islogical(OPTIONAL.normalize)
        error('normalize should be a boolean, got %s', class(OPTIONAL.normalize))
    end
else
    OPTIONAL.normalize = false;  % default
end

if isfield(OPTIONAL, 'half')
    if ~islogical(OPTIONAL.half)
        error('half should be a boolean, got %s', class(OPTIONAL.half))
    end
else
    OPTIONAL.half = false;  % default
end

if isfield(OPTIONAL, 'isotrope')
    if ~islogical(OPTIONAL.isotrope)
        error('half should be a boolean, got %s', class(OPTIONAL.isotrope))
    end
else
    OPTIONAL.isotrope = false;  % default
end

%% Create vectors with defined origin and shifts.
% For efficiency, shifts are applied to the boundaries and not to the vectors directly.
% On the other hand, normalization is done on the vectors, as rounding errors on the
% boundaries might lead to significative errors on the vectors.

% By default, the vectors are set to compute the real origin (origin = 0).
% To adjust for origin = 1|2, compute an offset to add to the vectors limits.
limits = zeros(2, ndim, 'single');
if OPTIONAL.origin > 0 || OPTIONAL.origin == -1
    if OPTIONAL.origin == 2
        direction = -1;
    else  % origin = -1 or 1
        direction = 1;
    end
    for dim = 1:ndim
        if ~mod(SIZE(dim), 2)  % even dimensions: shift half a pixel
            limits(1, dim) = -SIZE(dim)/2 + 0.5 - direction * 0.5;
            limits(2, dim) =  SIZE(dim)/2 - 0.5 - direction * 0.5;
        else  % odd dimensions
            limits(1, dim) = -SIZE(dim)/2 + 0.5;
            limits(2, dim) =  SIZE(dim)/2 - 0.5;
        end
    end
else  % OPTIONAL.origin == 0
    limits(1,:) = -SIZE./2 + 0.5;
    limits(2,:) =  SIZE./2 - 0.5;
end

% centered
if OPTIONAL.origin >= 0
    if (OPTIONAL.half)
        if any(OPTIONAL.shift)
            error('shifts are not allowed with half = true, got %s', mat2str(OPTIONAL.shift, 2))
        end
        if OPTIONAL.origin == 0 && ~mod(SIZE(1), 2)  % real center and even pixels
            vX = 0.5:single((SIZE(1)/2));
        else
            vX = 0:single(floor(SIZE(1)/2));
        end
    else
        vX = (limits(1, 1) - OPTIONAL.shift(1)):(limits(2, 1) - OPTIONAL.shift(1));
    end
    vY = (limits(1, 2) - OPTIONAL.shift(2)):(limits(2, 2) - OPTIONAL.shift(2));
    if (flg3d)
        vZ = (limits(1, 3) - OPTIONAL.shift(3)):(limits(2, 3) - OPTIONAL.shift(3));
    else
        vZ = nan;
    end

% not centered
else
    if any(OPTIONAL.shift)
        error('shifts are not allowed with origin = -1, got %s', mat2str(OPTIONAL.shift, 2))
    end
    if (OPTIONAL.half)
        vX = 0:single(floor(SIZE(1)/2));
    else
        vX = [0:limits(2,1), limits(1,1):-1];
    end
    vY = [0:limits(2,2), limits(1,2):-1];
    if (flg3d); vZ = [0:limits(2,3), limits(1,3):-1]; else; vZ = nan; end
end

if strcmpi(METHOD, 'gpu')
    vX = gpuArray(vX);
    vY = gpuArray(vY);
    if (flg3d); vZ = gpuArray(vZ); end
elseif ~strcmpi(METHOD, 'cpu')
    error("METHOD must be 'gpu' or 'cpu', got %s", METHOD);
end

if (OPTIONAL.isotrope)
    radius = min(abs(limits));
    radius_min = min(radius);
    vX = vX .* (radius_min / radius(1));
    vY = vY .* (radius_min / radius(2));
    if (flg3d); vZ = vZ .* (radius_min / radius(3)); else; vZ = nan; end
    if (OPTIONAL.normalize)
        size_min = min(SIZE);
        vX = vX ./ size_min;
        vY = vY ./ size_min;
        if (flg3d); vZ = vZ ./ size_min; end
    end
elseif (OPTIONAL.normalize)
    vX = vX ./ SIZE(1);
    vY = vY ./ SIZE(2);
    if (flg3d); vZ = vZ ./ SIZE(3); end
end

end  % EMC_multi_vectorCoordinates