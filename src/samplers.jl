# TODO (everywhere): instead of computing loval/(loval+hival), use 
#       1/(1+exp((lo-hi)*(alpha_i + ns_i)))
# TODO: explore how to use @inbounds, @inline, etc. to optimize performance in these fcns.
# TODO: for CFTP implementations, put in warnings that appear whenever any elements of Λ 
#       are negative.  In this case samples might still be useful if mixing time is similar
#       to the CFTP coalescence time, but exact sampling isn't guaranteed because the 
#       monotonicity property is lost.  Could also direct the user to cftp_bounding_chain()
#       ***CHECK: bounding chain method should work better for strong association case!!!*** 
#           --> It still can take very long, but initial trials suggest it might be a little
#               better at handling strong association.
#       ***CHECK: make sure my understanding of bounding chain construction is right***
#           --> Yes, we need to consider all configurations allowed by the bounding chain. 
#               But see my 2018-12-12 notes for how I implementeted it in cftp_bounding_chain()
# TODO: Implement Swendsen-Wang (either as a MC sampler or bounding chain-type perfect
#       sampler (see Huber16))
# TODO: at the end, try to specify a highest-level function that considers the situation
#       and chooses an algorithm.
# TODO: put in an optional "fudge factor" in cftp_bounding_chain, to tweak the local bounds to 
#       encourage convergence in large-association cases.  Need to think through what 
#       would be sensible to do here.  But since we do only a "local" bound based on 
#       the neighbor sums, we should have some hope of doing something useful with that
#       method. 
# TODO: Tests and checks for cftp_bounding_chain()


# Performance tip: writing the neighbor sum as a loop rather than an inner product
# saved lots of memory allocations.
function nbrsum(Λ, Y, μ, row, nbr)::Float64
    out = 0.0
    for ix in nbr
        out = out + Λ[row,ix] * (Y[ix] - μ[ix])
    end
    return out
end

function condprob(α, ns, lo, hi, ix)::Float64
    loval = exp(lo*(α[ix] + ns))
    hival = exp(hi*(α[ix] + ns))
    if hival==Inf
        return 1.0
    end
    return hival / (loval + hival)
end

function gibbsstep!(Y, lo, hi, Λ, adjlist, α, μ, n)
    ns = 0.0
    p_i = 0.0
    for i = 1:n
        ns = nbrsum(Λ, Y, μ, i, adjlist[i])
        p_i = condprob(α, ns, lo, hi, i)
        if rand() < p_i
            Y[i] = hi
        else
            Y[i] = lo
        end
    end
end

function gibbssample(lo::Float64, hi::Float64, Y::Vector{Float64}, 
                     Λ::SparseMatrixCSC{Float64,Int}, adjlist::Array{Array{Int64,1},1},
                     α::Vector{Float64}, μ::Vector{Float64}, n::Int, k::Int, average::Bool, 
                     start::Vector{Float64}, burnin::Int, verbose::Bool)

    temp = average ? zeros(Float64, n) : zeros(Float64, n, k-burnin)

    for j = 1:k
        gibbsstep!(Y, lo, hi, Λ, adjlist, α, μ, n)
        if average 
            # Performance tip: looping here saves memory allocations. (perhaps until we get
            # an operator like .+=)
            for i in 1:n
                temp[i] = temp[i] + Y[i]
            end
        elseif j > burnin
            for i in 1:n
                temp[i,j-burnin] = Y[i]
            end
        end
        if verbose 
            println("finished draw $(j) of $(k)") 
        end
    end
    if average
        return map(x -> (x - (k-burnin)*lo)/((k-burnin)*(hi-lo)), temp)
    else
        return temp
    end
end


function runepochs!(j, times, Y, seeds, lo, hi, Λ, adjlist, α, μ, n)
    # Run epochs from the jth one forward to time zero.
    for epoch = j:-1:0
        Random.seed!(seeds[j+1])
        for t = times[j+1,1] : times[j+1,2]
            gibbsstep!(Y, lo, hi, Λ, adjlist, α, μ, n)
        end
    end
end

function cftp_reuse_seeds(lo::Float64, hi::Float64, 
                    Λ::SparseMatrixCSC{Float64,Int}, adjlist::Array{Array{Int64,1},1},
                    α::Vector{Float64}, μ::Vector{Float64}, n::Int, k::Int, 
                    average::Bool, verbose::Bool)

    temp = average ? zeros(Float64, n) : zeros(Float64, n, k)
    T = 2      #-Initial number of time steps to go back.
    maxepoch = 40  #TODO: magic constant
    seeds = [UInt32[1] for i = 1:maxepoch+1]
    times = [-T * 2 .^(0:maxepoch) .+ 1  [0; -T * 2 .^(0:maxepoch-1)]]
    L = zeros(n)
    H = zeros(n)

    for rep = 1:k 
        seeds .= [[rand(UInt32)] for i = 1:maxepoch+1]
        coalesce = false    

        # Keep track of the seeds used.  seeds(j) will hold the seed used to generate samples
        # in "epochs" j = 0, 1, 2, ... going backwards in time from time zero. The 0th epoch
        # covers time steps -T + 1 to 0, and the jth epoch covers steps -(2^j)T+1 to -2^(j-1)T.
        # We'll cap j at 40 as T*2^40 is over a trillion time steps. 
        j = 0
        while ~coalesce
            fill!(L, lo)
            fill!(H, hi)
            runepochs!(j, times, L, seeds, lo, hi, Λ, adjlist, α, μ, n)
            runepochs!(j, times, H, seeds, lo, hi, Λ, adjlist, α, μ, n)
            coalesce = L==H
            if verbose 
                println("Started from -$(times[j+1,1]): $(sum(H .!= L)) elements different.")
            end
            j = j + 1
        end
        if !coalesce
            warning("Sampler did not coalesce. Returning NaNs.")  #TODO: fix for average case
            L .= fill(NaN, n)
        end
        if average && coalesce
            for i in 1:n
                temp[i] = temp[i] + L[i]
            end
        else
            for i in 1:n
                temp[i,rep] = L[i]
            end
        end
        if verbose 
            println("finished draw $(rep) of $(k)") 
        end
    end
    if average
        return map(x -> (x - k*lo)/(k*(hi-lo)), temp)
    else
        return temp
    end
end


function cftp_reuse_samples(lo::Float64, hi::Float64, 
                    Λ::SparseMatrixCSC{Float64,Int}, adjlist::Array{Array{Int64,1},1},
                    α::Vector{Float64}, μ::Vector{Float64}, n::Int, k::Int, 
                    average::Bool, verbose::Bool)

    temp = average ? zeros(Float64, n) : zeros(Float64, n, k)
    L = zeros(n)
    H = zeros(n)
    ns = 0.0
    p_i = 0.0

    # We use matrix U to hold all the uniform random numbers needed to compute the
    # lower and upper chains as stochastic recursive sequences. In this matrix each column
    # holds the n random variates needed to do a full Gibbs sampling update of the
    # variables in the graph. We think of the columns as going backwards in time to the
    # right: column one is time 0, column 2 is time -1, ... column T+1 is time -T.  So to
    # run the chains in forward time we go from right to left.
    for rep = 1:k 
        T = 2           #-T tracks how far back in time we start. Our sample is from time 0.
        U = rand(n,1)   #-Holds needed random numbers (this matrix will grow)
        coalesce = false    
        while ~coalesce
            fill!(L, lo)
            fill!(H, hi)
            U = [U rand(n,T)]
            for t = T+1:-1:1                          #-Column t corresponds to time -(t-1).
                for i = 1:n
                    # The lower chain
                    ns = nbrsum(Λ, L, μ, i, adjlist[i])
                    p_i = condprob(α, ns, lo, hi, i)
                    if U[i,t] < p_i
                        L[i] = hi
                    else
                        L[i] = lo
                    end
                    # The upper chain
                    ns = nbrsum(Λ, H, μ, i, adjlist[i])
                    p_i = condprob(α, ns, lo, hi, i)
                    if U[i,t] < p_i
                        H[i] = hi
                    else
                        H[i] = lo
                    end
                end
            end
            coalesce = L==H
            if verbose 
                println("Started from -$(T): $(sum(H .!= L)) elements different.")
            end
            T = 2*T
        end
        if average
            for i in 1:n
                temp[i] = temp[i] + L[i]
            end
        else
            for i in 1:n
                temp[i,rep] = L[i]
            end
        end
        if verbose 
            println("finished draw $(rep) of $(k)") 
        end
    end
    if average
        return map(x -> (x - k*lo)/(k*(hi-lo)), temp)
    else
        return temp
    end   
end

function cftp_read_once(lo::Float64, hi::Float64,  
                Λ::SparseMatrixCSC{Float64,Int}, adjlist::Array{Array{Int64,1},1},
                α::Vector{Float64}, μ::Vector{Float64}, n::Int, k::Int, 
                average::Bool, verbose::Bool)

    blocksize = blocksize_estimate(lo, hi, Λ, adjlist, α, μ, n)
    temp = average ? zeros(Float64, n) : zeros(Float64, n, k)
    L = zeros(n)
    H = zeros(n)
    Y = rand([lo, hi], n)
    U = zeros(n, blocksize)
    oldY = zeros(n)
  
    for rep = 0:k                      #-Run from zero because 1st draw is discarded.
        coalesce = false    
        while ~coalesce
            copyto!(oldY, Y)
            fill!(L, lo)
            fill!(H, hi)
            for i = 1:n          #-Performance: assigning to U in a loop uses 0 allocations.
                for j = 1:blocksize
                    U[i,j] = rand()
                end
            end
            gibbsstep_block!(Y, U, lo, hi, Λ, adjlist, α, μ)
            gibbsstep_block!(L, U, lo, hi, Λ, adjlist, α, μ)
            gibbsstep_block!(H, U, lo, hi, Λ, adjlist, α, μ)
            coalesce = L==H
            if verbose 
                println("Sample $(rep) coalesced? $(coalesce).")
            end
        end
        if rep > 0
            if average
                for i in 1:n
                    temp[i] = temp[i] + oldY[i]
                end
            else
                for i in 1:n
                    temp[i,rep] = oldY[i]
                end
            end
        end
    end
    if average
        return map(x -> (x - k*lo)/(k*(hi-lo)), temp)
    else
        return temp
    end   


end

function gibbsstep_block!(Z, U, lo, hi, Λ, adjlist, α, μ)
    ns = 0.0
    p_i = 0.0
    n, T = size(U)
    for t = 1:T
        for i = 1:n
            ns = nbrsum(Λ, Z, μ, i, adjlist[i])
            p_i = condprob(α, ns, lo, hi, i)
            if U[i,t] < p_i
                Z[i] = hi
            else
                Z[i] = lo
            end
        end
    end
end

function blocksize_estimate(lo, hi, Λ, adjlist, α, μ, n)
    nrep = 15   #TODO: magic constant
    coalesce_times = zeros(Int, nrep)
    L = zeros(n)
    H = zeros(n)
    U = zeros(n,1)
    for rep = 1:nrep
        coalesce = false
        fill!(L, lo)
        fill!(H, hi)
        count = one(Int)    
        while ~coalesce
            # Performance note: for filling U with random numbers, could i) loop through U
            # and fill each element; ii) assign with rand(n,1) on the RHS; or iii) use 
            # copyto!.  Option i) uses no allocations, but empirically seems slower.  Option
            # iii) seems fastest but requires allocation to produce the rand(n,1).
            copyto!(U, rand(n,1))
            gibbsstep_block!(L, U, lo, hi, Λ, adjlist, α, μ)
            gibbsstep_block!(H, U, lo, hi, Λ, adjlist, α, μ)
            coalesce = L==H
            count = count + 1
        end
        coalesce_times[rep] = count
    end
    return Int(round(quantile(coalesce_times, 0.6)))
end


function cftp_bounding_chain(lo::Float64, hi::Float64, 
                    Λ::SparseMatrixCSC{Float64,Int}, adjlist::Array{Array{Int64,1},1},
                    α::Vector{Float64}, μ::Vector{Float64}, n::Int, k::Int, 
                    average::Bool, verbose::Bool)

    temp = average ? zeros(Float64, n) : zeros(Float64, n, k)
    BC = Vector{Int}(undef,n)

    # We use matrix U to hold all the uniform random numbers needed to compute the
    # updates to the bounding chain. In this matrix each column
    # holds the n random variates needed to do a full Gibbs sampling update of the
    # variables in the graph. We think of the columns as going backwards in time to the
    # right: column one is time 0, column 2 is time -1, ... column T+1 is time -T.  So to
    # run the chains in forward time we go from right to left.
    for rep = 1:k 
        T = 2           #-T tracks how far back in time we start. Our sample is from time 0.
        U = rand(n,1)   #-Holds needed random numbers (this matrix will grow)
        coalesce = false    
        while ~coalesce
            # Initialize the bounding chain.  The state of the chain is represented by a vector of
            # length n, where each element can take values in the set {0, 1, 2}, where:
            #   - 0 inidicates that the single label "lo" is in the bounding chain for that vertex.
            #   - 1 indicates that the single label "hi" is in the bounding chain for that vertex.
            #   - 2 indicates that both labels {"lo", "hi"} are in the bounding chain.
            BC = fill(2,n)
            U = [U rand(n,T)]
            for t = T+1:-1:1                          #-Column t corresponds to time -(t-1).
                for i = 1:n
                    ss = 0.0  #"as small as possible" neighbor sum
                    sl = 0.0  #"as large as possible" neighbor sum
                    for j in adjlist[i]
                        λij = Λ[i,j]
                        if BC[j] == 2
                            if λij < 0
                                ss = ss + λij * (hi - μ[j])
                                sl = sl + λij * (lo - μ[j])
                            else
                                ss = ss + λij * (lo - μ[j])
                                sl = sl + λij * (hi - μ[j])
                            end
                        elseif BC[j] == 1
                            ss = ss + λij * (hi - μ[j])
                            sl = sl + λij * (hi - μ[j])
                        else
                            ss = ss + λij * (lo - μ[j])
                            sl = sl + λij * (lo - μ[j])
                        end
                    end
                    
                    pss = 1 / ( 1 + exp((lo-hi)*(α[i] + ss)) )
                    psl = 1 / ( 1 + exp((lo-hi)*(α[i] + sl)) )

                    check1 = U[i,t] < pss
                    check2 = U[i,t] < psl
                    if check1 && check2
                        BC[i] = 1
                    elseif check1 || check2 
                        BC[i] = 2
                    else
                        BC[i] = 0
                    end
                end
            end
            coalesce = all(BC .!= 2)
            if verbose 
                println("Started from -$(T): $(sum(BC .== 2)) elements not coalesced.")
            end
            T = 2*T
        end
        vals = [lo, hi]
        if average
            for i in 1:n
                temp[i] = temp[i] + vals[BC[i] + 1]
            end
        else
            for i in 1:n
                temp[i,rep] = vals[BC[i] + 1]
            end
        end
        if verbose 
            println("finished draw $(rep) of $(k)") 
        end
    end
    if average
        return map(x -> (x - k*lo)/(k*(hi-lo)), temp)
    else
        return temp
    end   
end



