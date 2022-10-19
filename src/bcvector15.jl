const l1_bits = 15
const max_levels = 3
const block_size_l1 = UInt64(1) << 15
const block_size_l2 = UInt64(1) << 31

struct BCVector
    num_frees::UInt64
    ints_l1::Vector{UInt16}
    ints_l2::Vector{UInt32}
    ints_l3::Vector{UInt64}
    ranks::NTuple{max_levels - 1, Vector{UInt64}}
    links::CVector
    leaves::BVector
end

function BCVector(bc_units, leaves)
    num_frees = 0
    ints_l1 = UInt16[]
    ints_l2 = UInt32[]
    ints_l3 = UInt64[]
    ranks = ntuple(i->UInt64[], max_levels - 1)
    links = UInt64[]

    function append_unit!(x)
        length(ints_l1) % block_size_l1 == 0 && push!(ranks[1], length(ints_l2))

        if fld(x, block_size_l1) == 0
            push!(ints_l1, (x << 1) % UInt16)
            return nothing
        else
            i = length(ints_l2) - ranks[1][end]
            push!(ints_l1, (0x1 | (i << 1)) % UInt16)
        end

        length(ints_l2) % block_size_l2 == 0 && push!(ranks[2], length(ints_l3))

        if fld(x, block_size_l2) == 0
            push!(ints_l2, (x << 1) % UInt32)
            return nothing
        else
            i = length(ints_l3) - ranks[2][end]
            push!(ints_l2, (0x1 | (i << 1)) % UInt32)
        end
        push!(ints_l3, x)
        return nothing
    end

    function append_leaf!(x)
        length(ints_l1) % block_size_l1 == 0 && push!(ranks[1], length(ints_l2))
        push!(ints_l1, x & 0xffff)
        push!(links, x >> 16)
        return nothing
    end

    for i = 1:(length(bc_units) >>> 1)
        i₀ = i - 1
        if leaves[i]
            append_leaf!(bc_units[BASE₁(i)])
        else
            append_unit!(bc_units[BASE₁(i)] ⊻ i₀)
        end
        append_unit!(bc_units[CHECK₁(i)] ⊻ i₀)
        bc_units[CHECK₁(i)] == i₀ && (num_frees += 1)
    end

    m_links = CVector(links)
    m_leaves = BVector(leaves, true, false)
    return BCVector(num_frees, ints_l1, ints_l2, ints_l3, ranks, m_links, m_leaves)
end

function access(bc::BCVector, i)
    i_ints_l1 = @inbounds bc.ints_l1[i + 1]
    x = i_ints_l1 >> 1
    i_ints_l1 & 0x1 == 0 && return UInt64(x)
    i = @inbounds bc.ranks[1][fld(i, block_size_l1) + 1] + x
    i_ints_l2 = @inbounds bc.ints_l2[i + 1]
    x = i_ints_l2 >> 1
    i_ints_l2 & 0x1 == 0 && return UInt64(x)
    i = @inbounds bc.ranks[2][fld(i, block_size_l2) + 1] + x
    return @inbounds bc.ints_l3[i + 1]
end

BASE₀(bc::BCVector, i) = access(bc, i << 1) ⊻ i
CHECK₀(bc::BCVector, i) = access(bc, i << 1 + 0x1) ⊻ i
LINK₀(bc::BCVector, i) = @inbounds bc.ints_l1[i << 1 + 0x1] | (bc.links[rank(bc.leaves, i) + 0x1] << 16)

isleaf(bc::BCVector, i) = @inbounds bc.leaves[i]
isused(bc::BCVector, i) = (i -= 1; CHECK₀(bc, i) != i)

num_units(bc::BCVector) = length(bc.ints_l1) >> 1
num_free_units(bc::BCVector) = bc.num_frees
num_nodes(bc::BCVector) = num_units(bc) - num_free_units(bc)
num_leaves(bc::BCVector) = bc.leaves.num_ones
