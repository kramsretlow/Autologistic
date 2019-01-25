# NOTE: @test_warn and @test_nowarn give Base.IOError exception when this 
# file is included in jupyter notebook.

# TODO: 
# [x] Decide whether values() is needed for interfaces, either delete or keep.
#     - Seems not needed for SimplePairwise. 
# [ ] Add more tests for getindex() with simplepairwise (many methods)

using Test
using LightGraphs, LinearAlgebra
using Autologistic

println("Running tests:")

@testset "FullUnary constructors and interfaces" begin
    M = [1.1 4.4 7.7
         2.2 5.5 8.8
         3.3 4.4 9.9]
    u1 = FullUnary(M[:,1])
    u2 = FullUnary(M)
    
    #@test values(u1) == reshape([1.1; 2.2; 3.3], (3,1))
    #@test values(u2) == M
    @test u1[2] == 2.2
    @test u2[2,3] == 8.8
    @test size(u1) == (3,1)
    @test size(u2) == (3,3)
    @test getparameters(u1) == [1.1; 2.2; 3.3]

    setparameters!(u1, [0.1, 0.2, 0.3])
    setparameters!(u2, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9])
    u1[2] = 2.22
    u2[2,3] = 8.88    

    #@test values(u1) == reshape([0.1, 2.22, 0.3], (3,1))
    #@test values(u2) == [0.1 0.4 0.7
    #                     0.2 0.5 8.88
    #                     0.3 0.6 0.9] 

    u3 = FullUnary(10)
    u4 = FullUnary(10,4)

    @test size(u3) == (10,1)
    @test size(u4) == (10,4)
end

@testset "LinPredUnary constructors and interfaces" begin
    X1 = [1.0 2.0 3.0
         1.0 4.0 5.0
         1.0 6.0 7.0
         1.0 8.0 9.0]
    X = cat(X1, 2*X1, dims=3)
    beta = [1.0, 2.0, 3.0]
    u1 = LinPredUnary(X, beta)
    u2 = LinPredUnary(X1, beta)
    u3 = LinPredUnary(X1)
    u4 = LinPredUnary(X)
    u5 = LinPredUnary(4, 3)
    u6 = LinPredUnary(4, 3, 2)
    Xbeta = [14.0 28.0
             24.0 48.0
             34.0 68.0
             44.0 88.0]
    X1beta = reshape(Xbeta[:,1], (4,1))

    @test size(u1) == size(u4) == size(u6) == (4,2)
    @test size(u2) == size(u3) == size(u5) == (4,1)
    #@test values(u1) == Xbeta 
    #@test values(u2) == X1beta
    @test u1[3,2] == u1[7] == 68.0
    @test getparameters(u1) == beta

    setparameters!(u1, [2.0, 3.0, 4.0])

    @test getparameters(u1) == [2.0, 3.0, 4.0]

end

@testset "SimplePairwise constructors and interfaces" begin
    n = 10                                                       # length of y_i
    m = 3                                                 # number of replicates
    λ = 1.0
    G = Graph(n, Int(floor(n*(n-1)/4)))
    p1 = SimplePairwise([λ], G, m)
    p2 = SimplePairwise(G)
    p3 = SimplePairwise(G, m)
    p4 = SimplePairwise(n)
    p5 = SimplePairwise(n, m)
    p6 = SimplePairwise(λ, G)
    p7 = SimplePairwise(λ, G, m)

    @test any(i -> (i!==(n,n,m)), [size(j) for j in [p1, p2, p3, p4, p5, p6, p7]])
    #@test values(p1) == values(p6) == values(p7) == λ*adjacency_matrix(G,Float64)
    @test p1[2,2,2] == p1[2,2] == λ*adjacency_matrix(G,Float64)[2,2]
    #@test p1[:,:,1] == p1[:,:,2] == p1[:,:,3] == values(p1)

    setparameters!(p1, [2.0])

    @test getparameters(p1) == [2.0]
end

@testset "AutologisticModel constructors" begin
    for r in [1 5]
        (n, p, m) = (100, 4, r)
        X = rand(n,p,m)
        β = [1.0, 2.0, 3.0, 4.0]
        Y = makebool(round.(rand(n,m)))
        unary = LinPredUnary(X, β)
        pairwise = SimplePairwise(n, m)
        coords = [(rand(),rand()) for i=1:n]
        m1 = AutologisticModel(Y, unary, pairwise, none, (-1.0,1.0), ("low","high"), coords)
        m2 = AutologisticModel(unary, pairwise)
        m3 = makeALRsimple(Graph(n, Int(floor(n*(n-1)/4))), X, Y=Y, β=β, λ = 1.0)

        @test getparameters(m3) == [β; 1.0]
        @test getunaryparameters(m3) == β
        @test getpairwiseparameters(m3) == [1.0]
        
        setparameters!(m1, [1.1, 2.2, 3.3, 4.4, -1.0])
        setunaryparameters!(m2, [1.1, 2.2, 3.3, 4.4])
        setpairwiseparameters!(m2, [-1.0])

        @test getparameters(m1) == getparameters(m2) == [1.1, 2.2, 3.3, 4.4, -1.0]
    end
end

@testset "Helper functions" begin
    # --- makebool() ---
    y1 = [false, false, true]
    y2 = [1 2; 1 2]
    y3 = [1.0 2.0; 1.0 2.0]
    y4 = ["yes", "no", "no"]
    @test makebool(y1) == reshape([false, false, true], (3,1))
    @test makebool(y2) == makebool(y3) == [false true; false true]
    @test makebool(y4) == reshape([true, false, false], (3,1))
end

@testset "almodel_functions" begin
    # --- makecoded() ---
    M1 = makeALRsimple(Graph(4,3), rand(4,2), 
                  Y=[true, false, false, true], coding=(-1,1))
    @test makecoded(M1) == reshape([1, -1, -1, 1], (4,1))
    @test makecoded(M1,[4, 3, 3, 4]) == reshape([1, -1, -1, 1], (4,1))

    # --- centeringterms() ---
    @test centeringterms(M1) == zeros(4,1)
    @test centeringterms(M1, onehalf) == ones(4,1)./2
    @test centeringterms(M1, expectation) == zeros(4,1)
    M2 = makeALRsimple(makegrid4(2,2)[1], ones(4,2,3), β = [1.0, 1.0], centering = expectation,
                   coding = (0,1), Y = repeat([true, true, false, false],1,3))
    @test centeringterms(M2) ≈ ℯ^2/(1+ℯ^2) .* ones(4,3)

    # --- negpotential() ---
    setpairwiseparameters!(M2, [1.0])
    @test negpotential(M2) ≈ 1.4768116880884703 * ones(3,1)
    
    # --- pseudolikelihood() ---
    X = [1.1 2.2
         1.0 2.0
         2.1 1.2
         3.0 0.3]
    Y = reshape([0, 0, 1, 0],(4,1))
    M3 = makeALRsimple(makegrid4(2,2)[1], cat(X,X,dims=3), Y=cat(Y,Y,dims=2), 
                   β=[-0.5, 1.5], λ=1.25, centering=expectation)
    @test pseudolikelihood(M3) ≈ 12.333549445795818
    
    # --- fullPMF() ---
    M4 = makeALRsimple(Graph(3,0), reshape([-1. 0. 1. -1. 0. 1.],(3,1,2)), β=[1.0])
    pmf = fullPMF(M4)
    probs = [0.0524968; 0.387902; 0.0524968; 0.387902; 0.00710467; 0.0524968;
             0.00710467; 0.0524968]
    @test pmf.partition ≈ 19.04878276433453 * ones(2)
    @test pmf.table[:,4,1] == pmf.table[:,4,2] 
    @test isapprox(pmf.table[:,4,1], probs, atol=1e-6)

    # --- marginalprobabilities() --- 
    truemp = [0.1192029 0.1192029; 0.5 0.5; 0.8807971 0.8807971]
    @test isapprox(marginalprobabilities(M4), truemp, atol=1e-6)
    @test isapprox(marginalprobabilities(M4,replicates=2), truemp[:,2], atol=1e-6)

    # --- conditionalprobabilities() --- 
    lam = 0.5
    a, b, c = (-1.2, 0.25, 1.5)
    y1, y2, y3 = (-1.0, 1.0, 1.0)
    ns1, ns2, ns3 = lam .* (y2+y3, y1+y3, y1+y2)
    cp1 = exp(a+ns1) / (exp(-(a+ns1)) + exp(a+ns1))
    cp2 = exp(b+ns2) / (exp(-(b+ns2)) + exp(b+ns2))
    cp3 = exp(c+ns3) / (exp(-(c+ns3)) + exp(c+ns3))
    M = AutologisticModel(FullUnary([a, b, c]), SimplePairwise(lam, Graph(3,3)), Y=[y1,y2,y3])
    @test isapprox(conditionalprobabilities(M), [cp1, cp2, cp3])
    @test isapprox(conditionalprobabilities(M, vertices=[1,3]), [cp1, cp3])
end

@testset "samplers" begin
    M5 = makeALRsimple(makegrid4(4,4)[1], rand(16,1))
    out1 = sample(M5, 10000, average=false)
    @test all(x->isapprox(x,0.5,atol=0.05), sum(out1.==1, dims=2)/10000)
    out2 = sample(M5, 10000, average=true, burnin=100, start=rand([1,2], 16))
    @test all(x->isapprox(x,0.5,atol=0.05), out2)

    M6 = makeALRsimple(makegrid4(3,3)[1], rand(9,2))
    setparameters!(M6, [-0.5, 0.5, 0.2])
    marg = marginalprobabilities(M6)
    out3 = sample(M6, 10000, method=perfect_read_once, average=true)
    out4 = sample(M6, 10000, method=perfect_reuse_samples, average=true)
    out5 = sample(M6, 10000, method=perfect_reuse_seeds, average=true)
    @test isapprox(out3, marg, atol=0.03, norm=x->norm(x,Inf))
    @test isapprox(out4, marg, atol=0.03, norm=x->norm(x,Inf))
    @test isapprox(out5, marg, atol=0.03, norm=x->norm(x,Inf))

    tbl = fullPMF(M6).table
    checkthree(x) = all(x[1:3] .== -1.0)
    threelow = sum(mapslices(x -> checkthree(x) ? x[10] : 0.0, tbl, dims=2))
    out6 = sample(M6, 10000, method=perfect_read_once, average=false)
    est6 = sum(mapslices(x -> checkthree(x) ? 1.0/10000.0 : 0.0, out6, dims=1))
    out7 = sample(M6, 10000, method=perfect_reuse_samples, average=false)
    est7 = sum(mapslices(x -> checkthree(x) ? 1.0/10000.0 : 0.0, out7, dims=1))
    out8 = sample(M6, 10000, method=perfect_reuse_seeds, average=false)
    est8 = sum(mapslices(x -> checkthree(x) ? 1.0/10000.0 : 0.0, out8, dims=1))
    @test isapprox(est6, threelow, atol=0.03)
    @test isapprox(est7, threelow, atol=0.03)
    @test isapprox(est8, threelow, atol=0.03)

end