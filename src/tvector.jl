struct TVector
    chars::Vector{UInt8}
    terms::BitVector
end

bin_mode(tv::TVector) = !isempty(tv.terms)

match(tv::TVector, key::AbstractString, tpos) = match(tv, codeunits(key), tpos)
function match(tv::TVector, key::AbstractVector{UInt8}, tpos)
    len = length(key)
    len == zero(UInt64) && return tpos == 1
    kpos = 1
    if bin_mode(tv)
        @inbounds while true
            key[kpos] != tv.chars[tpos] && return false
            tv.terms[tpos] && return kpos == len
            kpos += 1
            tpos += 1
            kpos <= len || break
        end
        return false
    else
        @inbounds while true
            c = tv.chars[tpos]
            (iszero(c) || key[kpos] != c) && return false
            kpos += 1
            tpos += 1
            kpos <= len || break
        end
        return @inbounds iszero(tv.chars[tpos])
    end
end

function decode(tv::TVector, tpos)
    isone(tpos) && return @view tv.chars[1:0]
    tpos_start = tpos
    len = length(tv.chars)
    if bin_mode(tv)
        @inbounds while tpos <= len && !tv.terms[tpos]
            tpos += 1
        end
        return @view tv.chars[tpos_start:min(tpos, len)]
    else
        @inbounds while tpos <= len && !iszero(tv.chars[tpos])
            tpos += 1
        end
        return @view tv.chars[tpos_start:min(tpos-1, len)]
    end
end

function decode!(tv::TVector, decoded::AbstractVector{UInt8}, tpos)
    tail = decode(tv, tpos)
    append!(decoded, tail)
    return decoded
end

function prefix_match(tv::TVector, key::AbstractVector{UInt8}, tpos)
    tpos == 1 && return 0
    length(key) == 0 && return nothing
    kpos = 1
    if bin_mode(tv)
        while true
            key[kpos] != tv.chars[tpos] && return nothing
            tv.terms[tpos] && return kpos
            kpos += 1
            tpos += 1
            kpos <= length(key) || break
        end
        return nothing
    else
        while true
            c = tv.chars[tpos]
            iszero(c) && return kpos - 1
            key[kpos] != tv.chars[tpos] && return nothing
            kpos += 1
            tpos += 1
            kpos <= length(key) || break
        end
        return iszero(tv.chars[tpos]) ? kpos - 1 : nothing
    end
end
