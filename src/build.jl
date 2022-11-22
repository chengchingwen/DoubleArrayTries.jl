const taboo_npos = 1
const free_blocks = 16

BASE₀(i) = UInt64(i) << 1
CHECK₀(i) = UInt64(i) << 1 + 0x1
BASE₁(i) = UInt64(i) << 1 - 0x1
CHECK₁(i) = UInt64(i) << 1

function min2gt(n)
    m = 1
    while m < n
        m <<= 1
    end
    return m
end

function use_unit!(m_units, m_useds, m_heads, m_l1_bits, npos)
    global taboo_npos
    m_useds[npos] = true
    next = m_units[BASE₀(npos)]
    prev = m_units[CHECK₀(npos)]
    m_units[BASE₀(prev)] = next
    m_units[CHECK₀(next)] = prev

    lpos = npos >>> m_l1_bits
    if m_heads[lpos] == npos
        m_heads[lpos] = (lpos != next >>> m_l1_bits) ? taboo_npos : next
    end
    return nothing
end

function code_table(m_keys)
    m_max_length = 0
    m_table    = based₀(Vector{UInt8}(undef, 512))
    m_alphabet = based₀(UInt8[])
    counter    = based₀(zeros(UInt64, 256))

    for key in m_keys
        for c in codeunits(key)
            counter[Int(c)] += 1
        end
        m_max_length = max(m_max_length, ncodeunits(key))
    end

    for (i, cf) in enumerate(counter)
        cf != 0 && push!(m_alphabet, UInt8(i-1))
    end

    perm = sortperm(counter; rev = true)
    for (i, c) in enumerate(perm)
        m_table[c] = UInt8(i-1)
    end
    for c = 0x00:0xff
        m_table[m_table[c] + 256] = c
    end
    return m_max_length, m_table, m_alphabet
end

function set_suffix!(m_suffixes, key, npos)
    @assert length(key) != 0 "The given suffix is empty"
    push!(m_suffixes, (str = key, npos = npos))
    return nothing
end


function is_target(m_useds, m_edges, m_table, base)
    for c in m_edges
        m_useds[base ⊻ m_table[c]] && return false
    end
    return true
end

function xcheck(m_units, m_l1_bits, m_useds, m_heads, m_edges, m_table, lpos)
    if m_units[BASE₀(taboo_npos)] == taboo_npos
        return (length(m_units) >>> 1) ⊻ m_table[m_edges[0]]
    end

    i = m_heads[lpos]
    while i != taboo_npos && i >>> m_l1_bits == lpos
        base = i ⊻ m_table[m_edges[0]]
        if is_target(m_useds, m_edges, m_table, base)
            return base
        end
        i = m_units[BASE₀(i)]
    end

    i = m_units[BASE₀(taboo_npos)]
    while i != taboo_npos
        base = i ⊻ m_table[m_edges[0]]
        if is_target(m_useds, m_edges, m_table, base)
            return base
        end
        i = m_units[BASE₀(i)]
    end
    return (length(m_units) >>> 1) ⊻ m_table[m_edges[0]]
end

function expand!(m_units, m_useds, m_heads, m_leaves, m_terms, m_l1_bits, m_l1_size)
    old_size = size(m_units, 2)
    new_size = old_size + 256

    for npos = old_size:(new_size - 1)
        push!(m_units, npos + 1, npos - 1)
    end
    append!(m_leaves, Iterators.repeated(false, length(old_size:new_size - 1)))
    append!(m_terms, Iterators.repeated(false, length(old_size:new_size - 1)))
    append!(m_useds, Iterators.repeated(false, length(old_size:new_size - 1)))

    last_npos = m_units[CHECK₀(taboo_npos)]
    m_units[CHECK₀(old_size)] = last_npos
    m_units[BASE₀(last_npos)] = old_size
    m_units[BASE₀(new_size - 1)] = taboo_npos
    m_units[CHECK₀(taboo_npos)] = new_size - 1

    for npos = old_size:m_l1_size:new_size-1
        push!(m_heads, npos)
    end

    bpos = old_size >>> 8
    if free_blocks <= bpos
        close_block!(m_units, m_useds, m_heads, m_l1_bits, m_l1_size, bpos - free_blocks)
    end
    return nothing
end

function close_block!(m_units, m_useds, m_heads, m_l1_bits, m_l1_size, bpos)
    beg_npos = bpos << 8
    end_npos = beg_npos + 256
    for npos in beg_npos:(end_npos-1)
        if !m_useds[npos]
            use_unit!(m_units, m_useds, m_heads, m_l1_bits, npos)
            m_useds[npos] = false
            m_units[BASE₀(npos)] = npos
            m_units[CHECK₀(npos)] = npos
        end
    end

    for npos = beg_npos:m_l1_size:(end_npos - 1)
        m_heads[npos >>> m_l1_bits] = taboo_npos
    end
    return nothing
end

function arrange!(m_units, m_l1_bits, m_l1_size, m_useds, m_terms, m_heads, m_leaves, m_edges, m_table, m_suffixes,
                  m_keys, begi, endi, kpos, npos)
    key = codeunits(m_keys[begi])
    if length(key) == kpos
        m_terms[npos] = true
        begi += 1
        if begi == endi
            m_units[BASE₀(npos)] = 0
            m_leaves[npos] = true
            return nothing
        end
    elseif begi + 1 == endi
        @assert length(key) > kpos "The input keys are not unique"
        m_terms[npos] = true
        m_leaves[npos] = true
        set_suffix!(m_suffixes, @view(key[(kpos + 1):end]), npos)
        return nothing
    end
    key = codeunits(m_keys[begi])

    empty!(m_edges)
    c = key[kpos + 1]
    for i = (begi + 1):(endi - 1)
        next_c = codeunit(m_keys[i], kpos + 1)
        if c != next_c
            @assert next_c >= c "The input keys are not in lexicographical order."
            push!(m_edges, c)
            c = next_c
        end
    end
    push!(m_edges, c)

    base = xcheck(m_units, m_l1_bits, m_useds, m_heads, m_edges, m_table, npos >>> m_l1_bits)
    (length(m_units) >>> 1) <= base && expand!(m_units, m_useds, m_heads, m_leaves, m_terms, m_l1_bits, m_l1_size)

    m_units[BASE₀(npos)] = base
    for c in m_edges
        child_id = base ⊻ m_table[c]
        use_unit!(m_units, m_useds, m_heads, m_l1_bits, child_id)
        m_units[CHECK₀(child_id)] = npos
    end

    i = begi
    c = key[kpos + 1]
    for j = (begi + 1):(endi - 1)
        next_c = codeunit(m_keys[j], kpos + 1)
        if c != next_c
            arrange!(m_units, m_l1_bits, m_l1_size, m_useds, m_terms, m_heads, m_leaves, m_edges, m_table, m_suffixes, m_keys,
                     i, j, kpos + 1, base ⊻ m_table[c])
            c = next_c
            i = j
        end
    end
    arrange!(m_units, m_l1_bits, m_l1_size, m_useds, m_terms, m_heads, m_leaves, m_edges, m_table, m_suffixes, m_keys,
             i, endi, kpos + 1, base ⊻ m_table[c])
    return nothing
end

function finish!(m_units, m_useds, m_heads, m_l1_bits, m_l1_size)
    npos = m_units[BASE₀(taboo_npos)]
    while npos != taboo_npos
        bpos = npos >>> 8
        close_block!(m_units, m_useds, m_heads, m_l1_bits, m_l1_size, bpos)
        npos = m_units[BASE₀(taboo_npos)]
    end
    return nothing
end

based₀(x) = OffsetArrays.Origin(0)(based₁(x))
based₁(x) = OffsetArrays.no_offset_view(x)

function buildXCDAT(_m_keys; l1_bits = 8, bin_mode = true)
    @assert bin_mode || all(key->all(!iszero, codeunits(key)), _m_keys) "`bin_mode = true` must be set if '\0' is included in a string key"
    m_keys = based₀(_m_keys)
    m_l1_bits = min(l1_bits, 8)
    m_l1_size = UInt(1) << m_l1_bits

    s = min2gt(length(m_keys))
    m_units    = based₀(Vector{UInt64}(undef, 2s))              |> empty!
    m_leaves   = based₀(falses(s))                              |> empty!
    m_terms    = based₀(falses(s))                              |> empty!
    m_useds    = based₀(falses(s))                              |> empty!
    m_heads    = based₀(Vector{UInt64}(undef, s >>> m_l1_bits)) |> empty!
    m_edges    = based₀(Vector{UInt8}(undef, 256 ))             |> empty!

    for npos = 0:255
        push!(m_units, (base  = mod(npos + 1, 256), check = mod(npos - 1, 256))...)
    end
    append!(m_leaves, Iterators.repeated(false, 256))
    append!(m_terms, Iterators.repeated(false, 256))
    append!(m_useds, Iterators.repeated(false, 256))

    for npos = 0:m_l1_size:255
        push!(m_heads, npos)
    end

    use_unit!(m_units, m_useds, m_heads, m_l1_bits, 0)
    m_units[CHECK₀(0)] = taboo_npos
    m_useds[taboo_npos] = true
    m_heads[taboo_npos >>> m_l1_bits] = m_units[BASE₀(taboo_npos)]

    m_max_length, m_table, m_alphabet = code_table(m_keys)
    isempty(m_alphabet) && error("No alphabet found in keys.")
    bin_mode |= iszero(m_alphabet[0])

    m_suffixes = based₀(@NamedTuple{str::AbstractVector{UInt8}, npos::UInt64}[])
    arrange!(m_units, m_l1_bits, m_l1_size, m_useds, m_terms, m_heads, m_leaves, m_edges, m_table, m_suffixes, m_keys,
             0, length(m_keys), 0, 0)

    finish!(m_units, m_useds, m_heads, m_l1_bits, m_l1_size)

    m_chars, m_tail_terms = complete!(m_suffixes, m_units, bin_mode, (m_units, npos, tpos)-> m_units[BASE₀(npos)] = tpos)
    return (
        based₁(m_units),
        based₁(m_leaves),
        based₁(m_terms),
        m_max_length,
        based₁(m_table),
        based₁(m_alphabet),
        based₁(m_suffixes),
        based₁(m_chars),
        based₁(m_tail_terms),
    )
end

_rget(str, i) = str[length(str) - i + 1]

function complete!(m_suffixes, m_units, bin_mode, func)
    m_terms = based₀(BitVector())
    sort!(m_suffixes; by=x->reverse(x.str))
    m_chars = based₀(UInt8[0])
    if bin_mode
        push!(m_terms, false)
    end

    prev_suffix = nothing
    prev_tpos = 0
    for i = length(m_suffixes):-1:1
        curr_suffix = m_suffixes[i - 1]
        suf_size = length(curr_suffix.str)
        @assert suf_size != 0 "A suffix is empty"

        match = 1
        prev_suf_size = isnothing(prev_suffix) ? 0 : length(prev_suffix.str)
        while match <= min(suf_size, prev_suf_size) && _rget(prev_suffix.str, match) == _rget(curr_suffix.str, match)
            match += 1
        end

        match₀ = match - 1
        if match₀ == suf_size && prev_suf_size != 0
            k = prev_tpos + (prev_suf_size - match₀)
            func(m_units, curr_suffix.npos, k)
            prev_tpos = k
        else
            c_len = length(m_chars)
            func(m_units, curr_suffix.npos, c_len)
            prev_tpos = c_len
            append!(m_chars, curr_suffix.str)
            if bin_mode
                append!(m_terms, Iterators.repeated(false, suf_size-1))
                push!(m_terms, true)
            else
                push!(m_chars, 0)
            end
        end

        prev_suffix = curr_suffix
    end
    return m_chars, m_terms
end
