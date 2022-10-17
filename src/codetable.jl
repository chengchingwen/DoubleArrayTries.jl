struct CodeTable
    max_length::Int
    table::Vector{UInt8}
    alphabet::Vector{UInt8}
end

alphabet_size(ct::CodeTable) = length(ct.alphabet)
max_length(ct::CodeTable) = ct.max_length

get_code(ct::CodeTable, c) = ct.table[Int(c) + 1]
get_char(ct::CodeTable, x) = ct.table[Int(x) + 257]
