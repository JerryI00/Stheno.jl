import Base: rand
import Distributions: logpdf, ContinuousMultivariateDistribution

export mean, cov, marginals, rand, logpdf, elbo

"""
    FiniteGP{Tf, Tx}

The finite-dimensional projection of the GP `f` at `x`.
"""
struct FiniteGP{Tf<:AbstractGP, Tx, Tσ²} <: ContinuousMultivariateDistribution
    f::Tf
    x::Tx 
    σ²::Tσ²
    function FiniteGP(f::AbstractGP, x::AV, σ²::Union{Real, AV{<:Real}})
        return new{typeof(f), typeof(x), typeof(σ²)}(f, x, σ²)
    end
end

"""
    mean(f::FiniteGP)

The mean vector of `f`.
"""
mean(f::FiniteGP) = map(mean(f.f), f.x)

"""
    cov(f::FiniteGP)

The covariance matrix of `f`.
"""
cov(f::FiniteGP) = pairwise(kernel(f.f), f.x) + _get_mat(f.σ²)

"""
    cov(f::FiniteGP, g::FiniteGP)

The cross-covariance between `f` and `g`.
"""
cov(f::FiniteGP, g::FiniteGP) = pairwise(kernel(f.f, g.f), f.x, g.x)

"""
    marginals(f::FiniteGP)

Sugar, returns a vector of Normal distributions representing the marginals of `f`.
"""
function marginals(f::FiniteGP)
    m, σ² = mean(f), map(kernel(f.f), f.x)
    return Normal.(mean(f), sqrt.(σ² .+ f.σ²))
end

"""
    rand(rng::AbstractRNG, f::FiniteGP, N::Int=1)

Obtain `N` independent samples from the GP `f` using `rng`.
"""
function rand(rng::AbstractRNG, f::FiniteGP, N::Int)
    μ, C = mean(f), cholesky(cov(f) + _get_mat(f.σ²))
    return μ .+ C.U' * randn(rng, length(μ), N)
end
rand(rng::AbstractRNG, f::FiniteGP) = vec(rand(rng, f, 1))
rand(f::FiniteGP, N::Int) = rand(Random.GLOBAL_RNG, f, N)
rand(f::FiniteGP) = vec(rand(f, 1))

"""
    logpdf(f::FiniteGP, y::AbstractVector{<:Real})

The log probability density of `y` under `f`.
"""
function logpdf(f::FiniteGP, y::AbstractVector{<:Real})
    μ, C = mean(f), cholesky(cov(f) + _get_mat(f.σ²))
    return -(length(y) * log(2π) + logdet(C) + Xt_invA_X(C, y - μ)) / 2
end

"""
    elbo(f::FiniteGP, y::AbstractVector{<:Real}, u::FiniteGP, σ::Real)

The saturated Titsias-ELBO. Requires a reasonable degree of care.
"""
function elbo(f::FiniteGP, y::AV{<:Real}, u::FiniteGP, σ::Real)
    Γ = (cholesky(cov(u)).U' \ cov(u, f)) ./ σ
    Ω, δ = cholesky(Γ * Γ' + I), y - mean(f)
    return -(length(y) * log(2π * σ^2) + logdet(Ω) - sum(abs2, Γ) +
        (sum(abs2, δ) - sum(abs2, Ω.U' \ (Γ * δ)) + sum(var, marginals(f))) / σ^2) / 2
end


##################################### Syntactic Sugar ######################################

# Specialised implementation of `rand` for `BlockGP`s.
function rand(rng::AbstractRNG, f::BlockGP, N::Int)
    M = BlockArray(undef_blocks, AbstractMatrix{Float64}, length.(f.fs), [N])
    μ = mean(f)
    for b in eachindex(f.fs)
        setblock!(M, getblock(μ, b) * ones(1, N), b, 1)
    end
    return M + chol(cov(f))' * BlockMatrix(randn.(Ref(rng), length.(f.fs), N))
end
rand(f::BlockGP, N::Int) = rand(Random.GLOBAL_RNG, f, N)

function rand(rng::AbstractRNG, f::BlockGP)
    return mean(f) + chol(cov(f))' * BlockVector(randn.(Ref(rng), length.(f.fs)))
end
rand(f::BlockGP) = rand(Random.GLOBAL_RNG, f)

# Convenience methods for invoking `logpdf` and `rand` with multiple processes.
rand(rng::AbstractRNG, fs::AV{<:AbstractGP}) = vec.(rand(rng, fs, 1))
rand(rng::AbstractRNG, fs::AV{<:AbstractGP}, N::Int) = rand(rng, BlockGP(fs), N).blocks
rand(fs::AV{<:AbstractGP}, N::Int) = rand(Random.GLOBAL_RNG, fs, N)
rand(fs::AV{<:AbstractGP}) = vec.(rand(Random.GLOBAL_RNG, fs))
logpdf(fs::AV{<:AbstractGP}, ys::AV{<:AV{<:Real}}) = logpdf(BlockGP(fs), BlockVector(ys))
