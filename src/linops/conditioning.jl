import Base: |
export ←, |

"""
    Observation

Represents fixing a paricular (finite) GP to have a particular (vector) value.
"""
struct Observation{Tf<:AbstractGP, Ty<:AbstractVector}
    f::Tf
    y::Ty
end
←(f, y) = Observation(f, y)

# """
#     |(g::Union{GP, Tuple{Vararg{GP}}}, c::Union{Observation, Tuple{Vararg{Observation}}})

# `|` is NOT bit-wise logical OR in this context, it is the conditioning operator. That is, it
# returns the conditional (posterior) distribution over everything on the left given the
# `Observation`(s) on the right.
# """
# |(g::GP, c::Observation) = ((g,) | (c,))[1]
# function |(g::GP, c::Observation)
#     f, y = c.f, c.y
#     f_q, X = f.args[1], f.args[2]
#     μf, kff = mean(f_q), kernel(f_q)
#     cache = CondCache(kff, μf, X, y)
#     return GP(|, g, f_q, cache)
# end
# μ_p′(::typeof(|), g::GP, f::GP, cache::CondCache) =
#     ConditionalMean(cache, mean(g), kernel(f, g))
# k_p′(::typeof(|), g::GP, f::GP, cache::CondCache) =
#     ConditionalKernel(cache, kernel(f, g), kernel(g))
# k_p′p((_, g, f, cache)::Tuple{typeof(|), GP, GP, CondCache}, h::GP) =
#     ConditionalCrossKernel(cache, kernel(f, g), kernel(f, h), kernel(g, h))
# k_pp′(h::GP, (_, g, f, cache)::Tuple{typeof(|), GP, GP, CondCache}) =
#     ConditionalCrossKernel(cache, kernel(f, h), kernel(f, g), kernel(h, g))

# # All of the code below is a stop-gap while I'm figuring out what to do about the
# # concatenation of GPs.
# |(g::GP, c::Observation) = ((g,) | (c,))[1]
# |(g::GP, c::Tuple{Vararg{Observation}}) = ((g,) | c)[1]
# |(g::Tuple{Vararg{GP}}, c::Observation) = g | (c,)
# function |(g::Tuple{Vararg{GP}}, c::Tuple{Vararg{Observation}})
#     f, y = [getfield.(c, :f)...], BlockVector([getfield.(c, :y)...])
#     f_qs, Xs = [f_.args[1] for f_ in f], [f_.args[2] for f_ in f]
#     μf = CatMean(mean.(f_qs))
#     kff = CatKernel(kernel.(f_qs), kernel.(f_qs, permutedims(f_qs)))
#     return map(g_->GP(|, g_, f_qs, CondCache(kff, μf, Xs, y)), g)
# end
# function μ_p′(::typeof(|), g::GP, f::Vector{<:GP}, cache::CondCache)
#     return ConditionalMean(cache, mean(g), CatCrossKernel(kernel.(f, Ref(g))))
# end
# function k_p′(::typeof(|), g::GP, f::Vector{<:GP}, cache::CondCache)
#     return ConditionalKernel(cache, CatCrossKernel(kernel.(f, Ref(g))), kernel(g))
# end
# function k_p′p(::typeof(|), g::GP, f::Vector{<:GP}, cache::CondCache, h::GP)
#     kfg, kfh = CatCrossKernel(kernel.(f, Ref(g))), CatCrossKernel(kernel.(f, Ref(h)))
#     return ConditionalCrossKernel(cache, kfg, kfh, kernel(g, h))
# end
# function k_pp′(h::GP, ::typeof(|), g::GP, f::Vector{<:GP}, cache::CondCache)
#     kfh, kfg = CatCrossKernel(kernel.(f, Ref(h))), CatCrossKernel(kernel.(f, Ref(g)))
#     return ConditionalCrossKernel(cache, kfh, kfg, kernel(h, g))
# end
# length(::typeof(|), f::GP, ::GP, f̂::Vector) = length(f)

"""
    |(g::AbstractGP, c::Observation)

Condition `g` on observation `c`.
"""
function |(g::GP, c::Observation)
    f_finite, y = c.f, c.y
    f, X = f_finite.args[1], f_finite.args[2]
    return GP(|, g, f, CondCache(kernel(f), mean(f), X, y))
end
function |(g::JointGP, c::Observation)
    
end

function μ_p′(::typeof(|), g::AbstractGP, f::AbstractGP, cache::CondCache)
    return ConditionalMean(cache, mean(g), kernel(f, g))
end
function k_p′(::typeof(|), g::AbstractGP, f::AbstractGP, cache::CondCache)
    return ConditionalKernel(cache, kernel(f, g), kernel(g))
end
function k_p′p(::typeof(|), g::AbstractGP, f::AbstractGP, cache::CondCache, h::AbstractGP)
    return ConditionalCrossKernel(cache, kernel(f, g), kernel(f, h), kernel(g, h))
end
function k_pp′(h::AbstractGP, ::typeof(|), g::AbstractGP, f::AbstractGP, cache::CondCache)
    return ConditionalCrossKernel(cache, kernel(f, h), kernel(f, g), kernel(h, g))
end


abstract type AbstractConditioner end

"""
    Titsias <: AbstractConditioner

Construct an object which is able to compute an approximate posterior.
"""
struct Titsias{Tu<:AbstractGP, TZ<:AVM, Tm<:AV{<:Real}, Tγ} <: AbstractConditioner
    u::Tu
    Z::TZ
    m′u::Tm
    γ::Tγ
    function Titsias(u::Tu, Z::TZ, m′u::Tm, Σ′uu::AM, gpc::GPC) where {Tu, TZ, Tm}
        γ = GP(FiniteKernel(Xtinv_A_Xinv(Σ′uu, cov(u, Z))), gpc)
        return new{Tu, TZ, Tm, typeof(γ)}(u, Z, m′u, γ)
    end
end
function |(g::GP, c::Titsias)
    g′ = g | (c.u(c.Z)←c.m′u)
    ϕ = LhsFiniteCrossKernel(kernel(c.u, g), c.Z)
    ĝ = project(ϕ, c.γ, 1:length(c.m′u), ZeroMean{Float64}())
    return return g′ + ĝ
end

function optimal_q(
    f::AV{<:GP}, X::AV{<:AVM}, y::BlockVector{<:Real},
    u::AV{<:GP}, Z::AV{<:AVM},
    σ::Real,
)
    μᵤ, Σᵤᵤ = mean(u, Z), cov(u, Z)
    U = chol(Σᵤᵤ)
    Γ = (U' \ xcov(u, f, Z, X)) ./ σ
    Ω, δ = LazyPDMat(Γ * Γ' + I, 0), y - mean(f, X)
    Σ′ᵤᵤ = Xt_invA_X(Ω, U)
    μ′ᵤ = μᵤ + (U' * (Ω \ (Γ * δ))) / σ
    return μ′ᵤ, Σ′ᵤᵤ
end
