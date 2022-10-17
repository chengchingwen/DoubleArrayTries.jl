struct CVector <: AbstractVector{UInt64}
    size::UInt64
    bits::UInt64
    mask::UInt64
    chunks::Vector{UInt64}
end

function needed_bits(x)
    (x == 0 ? 0 : 63 - leading_zeros(x)) + 1
end

function CVector(vec::AbstractVector)
    @assert length(vec) != 0
    m_size = length(vec)
    m_bits = needed_bits(maximum(vec))
    m_mask = (UInt64(1) << m_bits) - 1
    chunks = Vector{UInt64}(undef, (m_size * m_bits + 63) >> 6)
    for i = 0:m_size-1
        val = vec[i + 1]
        quo, mod = fldmod(i * m_bits, 64)
        chunks[quo + 1] &= ~(m_mask << mod)
        chunks[quo + 1] |= (val & m_mask) << mod
        if 64 < mod + m_bits
            diff = 64 - mod
            chunks[quo + 2] &= ~(m_mask >> diff)
            chunks[quo + 2] |= (val & m_mask) >> diff
        end
    end
    return CVector(m_size, m_bits, m_mask, chunks)
end

Base.length(cv::CVector) = cv.size
Base.size(cv::CVector) = (length(cv),)

Base.checkbounds(::Type{Bool}, cv::CVector, i) = i <= length(cv)

@inline function Base.getindex(cv::CVector, i)
    @boundscheck checkbounds(cv, i)
    i = UInt64(i - 1)
    quo, mod = fldmod(i * cv.bits, 64)
    @inbounds if mod + cv.bits <= 64
        return (cv.chunks[quo + 1] >> mod) & cv.mask
    else
        return ((cv.chunks[quo + 1] >> mod) | (cv.chunks[quo + 2] << (64 - mod))) & cv.mask
    end
end
