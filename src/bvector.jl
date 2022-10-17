const block_size = 8
const selects_per_hint = 64 * block_size * 2

struct BVector <: AbstractVector{Bool}
    num_ones::UInt64
    data::BitVector
    rank_hints::Vector{UInt64}
    select_hints::Vector{UInt64}
end

BVector(data::AbstractVector{Bool}, args...) = BVector(BitVector(data), args...)
function BVector(data::BitVector, enable_rank = true, enable_select = true)
    num_ones = count(data)
    rank_hints = enable_rank ? build_rank_hints(data) : UInt64[]
    select_hints = enable_rank && enable_select ? build_select_hints(data, rank_hints) : UInt64[]
    return BVector(num_ones, data, rank_hints, select_hints)
end

Base.axes(bv::BVector) = axes(bv.data)
Base.length(bv::BVector) = length(bv.data)
Base.getindex(bv::BVector, i...) = bv.data[i...]

function rank(bv::BVector, i)
    @assert !isempty(bv.rank_hints)
    i >= length(bv) && return bv.num_ones
    wi, wj = fldmod(i, 64)
    return rank_for_word(bv, wi) + UInt64(wj != 0 ? count_ones(bv.data.chunks[wi + 1] << (64 - wj)) : 0)
end

function rank_for_word(bv::BVector, wi)
    bi, bj = fldmod(wi, block_size)
    rank_for_block = @inbounds bv.rank_hints[2bi + 1]
    rank_in_block = @inbounds (bv.rank_hints[2bi + 2] >> ((7 - bj) * 9)) & 0x1ff
    return rank_for_block + rank_in_block
end

# function rank_for_block(rank_hints, bi)
#   return rank_hints[2bi - 1]₁
# end
# function rank_in_block(rank_hints, bi)
#   return rank_hints[2bi]₁
# end

function select(bv::BVector, n)
    @assert !isempty(bv.rank_hints) && !isempty(bv.select_hints)
    @assert n < bv.num_ones
    bi = select_for_block(bv, n)
    @assert bi < num_blocks(bv.rank_hints)
    curr_rank = @inbounds bv.rank_hints[2bi + 1]
    @assert curr_rank <= n
    rank_in_block_parallel = (UInt64(n) - curr_rank) * ones_step_9
    sub_ranks = @inbounds bv.rank_hints[2bi + 2]
    sub_block_offset =
        ((uleq_step_9(sub_ranks, rank_in_block_parallel) * ones_step_9) >> 54) & 0x7
    curr_rank += (sub_ranks >> ((UInt64(7) - sub_block_offset) * 9)) & 0x1ff
    @assert curr_rank <= n
    word_offset = (bi * block_size) + sub_block_offset
    chunk = @inbounds bv.data.chunks[word_offset+1]
    return 64word_offset + select_in_word(chunk, UInt64(n) - curr_rank)
end

function select_for_block(bv, n)
    a, b = select_with_hint(bv.select_hints, n)
    @inbounds while b - a > 1
        lb = Base.midpoint(a, b)
        if bv.rank_hints[2lb + 1] <= n
            a = lb
        else
            b = lb
        end
    end
    return a
end

function select_with_hint(select_hints, n)
    i = div(n, selects_per_hint)
    a = @inbounds iszero(i) ? UInt64(0) : select_hints[i]
    b = @inbounds select_hints[i+1] + 0x1
    return a, b
end

num_blocks(m_rank_hints) = length(m_rank_hints) >>> 0x1 - 1

function build_rank_hints(m_bits)
    curr_num_ones = 0
    curr_num_ones_in_block = 0
    curr_ranks_in_block = 0

    chunks = m_bits.chunks
    num_words = length(chunks)
    rank_hints = UInt64[ curr_num_ones ]

    for wi = 1:num_words
        bi = mod1(wi, block_size)
        num_ones_in_word = count_ones(chunks[wi])
        if bi != 1
            curr_ranks_in_block <<= 9
            curr_ranks_in_block |= curr_num_ones_in_block
        end
        curr_num_ones          += num_ones_in_word
        curr_num_ones_in_block += num_ones_in_word
        if bi == block_size
            push!(rank_hints, curr_ranks_in_block, curr_num_ones)
            curr_num_ones_in_block = 0
            curr_ranks_in_block = 0
        end
    end

    padding = num_words % block_size
    remain = block_size - padding
    for wi = 1:remain
        curr_ranks_in_block <<= 9
        curr_ranks_in_block |= curr_num_ones_in_block
    end
    push!(rank_hints, curr_ranks_in_block)
    padding > 0 && push!(rank_hints, curr_ranks_in_block, 0)
    return rank_hints
end

function build_select_hints(data, m_rank_hints)
    select_hints = Vector{UInt64}()
    threshold = UInt64(selects_per_hint)
    num_block = num_blocks(m_rank_hints)
    for bi in 1:num_block
        if m_rank_hints[2bi + 1] > threshold
            push!(select_hints, bi-1)
            threshold += selects_per_hint
        end
    end
    push!(select_hints, num_block)
    return select_hints
end
