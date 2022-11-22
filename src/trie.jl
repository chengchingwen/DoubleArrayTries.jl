struct DoubleArrayTrie
    num_keys::Int
    bcvec::BCVector
    table::CodeTable
    terms::BVector
    tvec::TVector
end

DoubleArrayTrie(m_keys::AbstractVector{<:AbstractString}; bin_mode = true) = DoubleArrayTrie(collect(m_keys); bin_mode)
function DoubleArrayTrie(m_keys::Vector{<:AbstractString}; bin_mode = true)
    !issorted(m_keys) && sort!(m_keys)
    !allunique(m_keys) && unique!(m_keys)
    m_units, m_leaves, m_terms, m_max_length, m_table, m_alphabet, m_suffixes, m_chars, m_tail_terms = buildXCDAT(m_keys; bin_mode)
    num_keys = length(m_keys)
    bcvec = BCVector(m_units, m_leaves)
    table = CodeTable(m_max_length, m_table, m_alphabet)
    terms = BVector(m_terms)
    tvec = TVector(m_chars, m_tail_terms)
    return DoubleArrayTrie(num_keys, bcvec, table, terms, tvec)
end

bin_mode(dat::DoubleArrayTrie) = bin_mode(dat.tvec)
num_keys(dat::DoubleArrayTrie) = dat.num_keys
alphabet_size(dat::DoubleArrayTrie) = alphabet_size(dat.table)
max_length(dat::DoubleArrayTrie) = max_length(dat.table)
num_nodes(dat::DoubleArrayTrie) = num_nodes(dat.bcvec)
num_units(dat::DoubleArrayTrie) = num_units(dat.bcvec)
num_free_units(dat::DoubleArrayTrie) = num_free_units(dat.bcvec)
tail_length(dat::DoubleArrayTrie) = length(dat.tvec.chars)

npos_to_id(dat::DoubleArrayTrie, npos) = Int(rank(dat.terms, npos - 1)) + 1
id_to_npos(dat::DoubleArrayTrie, npos) = Int(select(dat.terms, npos - 1)) + 1

lookup(dat::DoubleArrayTrie, key::AbstractString) = lookup(dat, codeunits(key))
function lookup(dat::DoubleArrayTrie, key::AbstractVector{UInt8})
    len = length(key)
    kpos = npos = UInt64(1)
    @inbounds while !isleaf(dat.bcvec, npos)
        kpos == len + 1 && return dat.terms[npos] ? npos_to_id(dat, npos) : 0
        npos₀ = npos - 1
        cpos₀ = BASE₀(dat.bcvec, npos₀) ⊻ get_code(dat.table, key[kpos])
        kpos += 1
        CHECK₀(dat.bcvec, cpos₀) != npos₀ && return 0
        npos = cpos₀ + 1
    end
    tpos = Int(LINK₀(dat.bcvec, npos - 1)) + 1
    suffix = @inbounds @view key[kpos:end]
    match(dat.tvec, suffix, tpos) || return 0
    return npos_to_id(dat, npos)
end

function decode(dat::DoubleArrayTrie, i)
    (0 < i <= dat.num_keys) || return nothing
    decoded = Vector{UInt8}(undef, max_length(dat)) |> empty!
    decode!(dat, decoded, i)
    return String(decoded)
end

function decode!(dat::DoubleArrayTrie, decoded::AbstractVector{UInt8}, i)
    (0 < i <= dat.num_keys) || return decoded
    r_start = length(decoded) + 1
    npos = id_to_npos(dat, i)
    tpos₀ = isleaf(dat.bcvec, npos) ? LINK₀(dat.bcvec, npos - 1) : typemax(UInt64)
    npos₀ = UInt64(npos - 1)
    while npos₀ != 0
        ppos₀ = CHECK₀(dat.bcvec, npos₀)
        push!(decoded, get_char(dat.table, BASE₀(dat.bcvec, ppos₀) ⊻ npos₀))
        npos₀ = ppos₀
    end
    reverse!(decoded, r_start)
    if tpos₀ != 0 && tpos₀ != typemax(UInt64)
        decode!(dat.tvec, decoded, tpos₀ + 1)
    end
    return decoded
end

Base.length(dat::DoubleArrayTrie) = num_keys(dat)
function Base.iterate(dat::DoubleArrayTrie, state = nothing)
    it = isnothing(state) ? iterate(PredictiveSearch(dat, "")) : iterate(PredictiveSearch(dat, ""), state)
    isnothing(it) && return nothing
    (id, decoded), nstate = it
    return decoded => id, nstate
end
