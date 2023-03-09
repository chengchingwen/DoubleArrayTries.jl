using Preferences

const ones_step_4 = 0x1111111111111111
const ones_step_8 = 0x0101010101010101
const ones_step_9 = 0x0040201008040201 # 1 << 0 | 1 << 9 | 1 << 18 | 1 << 27 | 1 << 36 | 1 << 45 | 1 << 54
const msbs_step_8 = 0x80 * ones_step_8
const msbs_step_9 = ones_step_9 << 8

function uleq_step_9(x::UInt64, y::UInt64)
    return (((((y | msbs_step_9) - (x & ~msbs_step_9)) | (x ⊻ y)) ⊻ (x & ~y)) & msbs_step_9) >> 8
end

const use_pdep = @load_preference("use_pdep", true)

function set_native_pdep_support(b::Bool)
    @set_preferences!("use_pdep" => b)
    if has_bmi2()
        cond = b ? "enable" : "disable"
        @info "$cond native pdep instrunction; restart your Julia session for this change to take effect!"
    else
        @info "CPU doesn't support native pdep instrunction; nothing changed."
    end
end

use_pdep_inst() = use_pdep && has_bmi2()

function has_bmi2()
    try
        CPUInfo = zeros(Int32, 4)
        ccall(:jl_cpuidex, Cvoid, (Ptr{Cint}, Cint, Cint), CPUInfo, 7, 0)
        return CPUInfo[2] & 0x100 != 0
    catch
        return false
    end
end

@static if use_pdep_inst()
    select_in_word(x, k) = pdep_select_in_word(x, k)
    pdep(x::UInt32, y::UInt32) = ccall("llvm.x86.bmi.pdep.32", llvmcall, UInt32, (UInt32, UInt32), x, y)
    pdep(x::UInt64, y::UInt64) = ccall("llvm.x86.bmi.pdep.64", llvmcall, UInt64, (UInt64, UInt64), x, y)
else
    select_in_word(x, k) = tabled_select_in_word(x, k)
    pdep(x::T, y::T) where {T <: Union{UInt32, UInt64}} = _pdep(x, y)
end

include("bytetable.jl")
const select_in_bytes_table = byte_table()

function select_in_bytes(i)
    global select_in_bytes_table
    bi, bj = fldmod1(i, 16)
    return (select_in_bytes_table[bi] >> 4(bj - 1)) & 0xf
end

function tabled_select_in_word(x, k)
    byte_sums = byte_counts(x) * ones_step_8
    k_step_8 = k * ones_step_8
    geq_k_step_8 = (((k_step_8 | msbs_step_8) - byte_sums) & msbs_step_8)
    place = count_ones(geq_k_step_8) * 8
    byte_rank = k - (((byte_sums << 8) >> place) & 0xff)
    bi = (((x >> place) & 0xff) | (byte_rank << 8))
    return place + select_in_bytes(bi + 1)
end

function byte_counts(x::UInt64)
    x = x - ((x & (UInt64(0xa) * ones_step_4)) >> UInt64(1));
    x = (x & (UInt64(3) * ones_step_4)) + ((x >> UInt64(2)) & (UInt64(3) * ones_step_4));
    x = (x + (x >> UInt64(4))) & (UInt64(0x0f) * ones_step_8);
    return x;
end

pdep_select_in_word(x, k) = UInt64(trailing_zeros(pdep(UInt64(1) << UInt64(k), UInt64(x))))

function _pdep(temp::T, mask::T) where T <: Union{UInt32, UInt64}
    n = count_ones(mask)
    if n < 4
        return __pdep(Val(1), temp, mask)
    elseif n < 8
        return __pdep(Val(2), temp, mask)
    else
        return __pdep(Val(4), temp, mask)
    end
end

@generated function __pdep(::Val{N}, temp::T, mask::T) where {N, T <: Union{UInt32, UInt64}}
    operand_size = T(sizeof(T) << 3)
    shn = operand_size - 0x1
    count_ones(N) != 1 && return quote error("__pdep N must be power of 2") end
    bit = trailing_zeros(N)
    b = operand_size >> bit
    unroll_masks = [:($(Symbol(:lowest, i)) = -mask & mask; mask ⊻= $(Symbol(:lowest, i))) for i in 1:N]
    unroll_lsbs = [:($(Symbol(:lsb, i+1)) = unsigned(signed(temp << $(shn-i)) >> $(shn+i))) for i in 0:N-1]
    update = Expr(:call, :|, map(i->:($(Symbol(:lsb, i)) & $(Symbol(:lowest, i))), 1:N)...)
    dest_upt = :(dest |= $update)
    ret = N == 1 ? :(iszero(lowest1) && return dest) : :(iszero(mask) && return dest)
    temp_upt = :(temp >>>= $N)
    unroll = quote
        $(unroll_masks...)
        $(unroll_lsbs...)
        $dest_upt
        $ret
        $temp_upt
    end
    unroll_expr = quote
        while true
            $unroll
        end
    end
    return quote
        dest = zero(T)
        $unroll_expr
    end
end
