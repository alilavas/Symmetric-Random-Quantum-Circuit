module GKToolboxv3
#-------------------------------------------------
#-------------------------------------------------
using LinearAlgebra;
using Random;
using Distributed

export EntanglementData
export mineTheDataU_Ancilla_v2


#-------------------------------------------------
#-------------------------------------------------
# GF2 = ResidueRing(ZZ, 2)
#-------------------------------------------------
#-------------------------------------------------
mutable struct EntanglementData
    n_id::Int64
    p_unitary_id::Int64
    p_single_id::Int64
    s_topo::Array{Float64,2}
    ancillaEntropy::Array{Float64,2}
    quarterLengthEnt::Array{Float64,2}
    halfLengthEnt::Array{Float64,2}
    finalEntProf::Array{Float64,2}
    ensembleSize::Int64
    timeConsumed::Float64
    EntanglementData()=new()
end
#-------------------------------------------------
#-------------------------------------------------
function mineTheDataU_Ancilla_v2(ns,p_unitaries,p_singles, ensembleSize, resultsChannel)
    r=EntanglementData()
    r.ensembleSize=ensembleSize
    for n_id in eachindex(ns)
        n=ns[n_id]
        r.n_id=n_id
        for p_unitary_id in eachindex(p_unitaries)
            p_unitary=p_unitaries[p_unitary_id]
            r.p_unitary_id=p_unitary_id

            for p_single_id in eachindex(p_singles)
                p_single=p_singles[p_single_id]
                r.p_single_id=p_single_id

                if p_single+p_unitary>1+1e-10
                    continue
                end

                #gather the data
                r.timeConsumed= @elapsed r.s_topo,r.quarterLengthEnt,r.halfLengthEnt,r.finalEntProf,r.ancillaEntropy= simulateGKU_Ancilla_v2(n,p_unitary,p_single,ensembleSize)
                if myid()==1
                    put!(resultsChannel, deepcopy(r))
                else
                    put!(resultsChannel, r)
                end
            end
        end
    end
end

#-------------------------------------------------
#-------------------------------------------------
function simulateGKU_Ancilla_v2(n,p_unitary,p_single,ensembleSize)

    #triple qubit stabilizers to be measured
    orgStab,=initStabSPT(n)
    orgStab=hcat(orgStab[:,1:n],zeros(Int8,n),orgStab[:,n+1:2n],zeros(Int8,n))

    duration=2n
    purificationTime=n



    #single qubit stabilizers to be measured
    mg,=initStabProd(n)
    mg=hcat(mg[:,1:n],zeros(Int8,n),mg[:,n+1:2n],zeros(Int8,n))

    L=n÷4
    A=collect(1:L)
    B=collect(L+1:2*L)
    D=collect(2*L+1:3*L)
    C=collect(3*L+1:n)


    entData=zeros(Float64, duration,2)
    quarterLengthEnt=zeros(Float64, duration,2)
    halfLengthEnt=zeros(Float64, duration,2)
    finalEntProf=zeros(Float64, n+1 , 2)
    ancillaEntropy=zeros(Float64, purificationTime,2)

    for r in  1:ensembleSize

        #initialize stabilizer state

        stab,sign=initStabProd_Ancilla(n)
        stab,sign=initStabProd(n+1)
        uSign=zeros(Int8,6)

        for t in 1:duration

            qEt=entanglement(stab,A)
            quarterLengthEnt[t,1]+=qEt
            quarterLengthEnt[t,2]+=qEt^2

            hEt=entanglement(stab,[A;B])
            halfLengthEnt[t,1]+=hEt
            halfLengthEnt[t,2]+=hEt^2

            et=hEt+entanglement(stab,[B;C])-entanglement(stab,B)-entanglement(stab,D)
            entData[t,1]+=et
            entData[t,2]+=et^2

            for _ in 1:n
                triple_coin=rand()
                if triple_coin<=p_unitary
                    i=rand(1:n-2)
                    uApply3qubitUnitary!(stab,sign,SPTU3s[rand(1:sptu3Num)],uSign,i,i+1,i+2)
                elseif triple_coin<=p_unitary+p_single
                    i=rand(1:n)
                    updateStab!(stab,sign,mg[i,:])

                else
                    i=rand(1:n)
                    updateStab!(stab,sign,orgStab[i,:])
                end
            end
        end

        for i in 1:n+1
            ep=entanglement(stab,collect(1:i-1))
            finalEntProf[i,1]+=ep
            finalEntProf[i,2]+=ep^2
        end

        ancillaStab1=zeros(Int8,2*(n+1))
        ancillaStab2=zeros(Int8,2*(n+1))
        ancillaStab3=zeros(Int8,2*(n+1))

        #X_{n/2-1} X_A X_{n/2+1}
        ancillaStab1[n÷2-1]=1
        ancillaStab1[n÷2+1]=1
        ancillaStab1[n+1]=1

        #Z_{n/2-1} Z_A
        ancillaStab2[n+1+n÷2-1]=1
        ancillaStab2[n+1+n+1]=1

        #Z_A Z_{n/2+1}
        ancillaStab3[n+1+n÷2+1]=1
        ancillaStab3[n+1+n+1]=1


        # entangle the ancilla
        updateStab!(stab,sign,ancillaStab1)
        updateStab!(stab,sign,ancillaStab2)
        updateStab!(stab,sign,ancillaStab3)

        for t in 1:purificationTime

            aet=entanglement(stab,[n+1])
            ancillaEntropy[t,1]+=aet
            ancillaEntropy[t,2]+=aet^2

            for _ in 1:n
                triple_coin=rand()
                if triple_coin<=p_unitary
                    i=rand(1:n-2)
                    uApply3qubitUnitary!(stab,sign,SPTU3s[rand(1:sptu3Num)],uSign,i,i+1,i+2)
                elseif triple_coin<=p_unitary+p_single
                    i=rand(1:n)
                    updateStab!(stab,sign,mg[i,:])
                else
                    i=rand(1:n)
                    updateStab!(stab,sign,orgStab[i,:])
                end
            end
        end
    end

    return entData,quarterLengthEnt,halfLengthEnt,finalEntProf,ancillaEntropy

end
#-------------------------------------------------
#-------------------------------------------------
function updateStab!(stab,sign,g)
    n,=size(stab)

    gX=view(g,1:n)
    gZ=view(g,n+1:2*n)
    stabX=view(stab,:,1:n)
    stabZ=view(stab,:,n+1:2*n)

    nonCummuting=(stabX*gZ+stabZ*gX).%2

    i=1
    while i<=n
        nonCummuting[i]==0 ? i+=1 : break
    end
    if i>n return end

    for j in i+1:n
        if nonCummuting[j]!=0
            stabX[j,:].⊻=stabX[i,:]
            stabZ[j,:].⊻=stabZ[i,:]
            # sign[j]⊻=(sign[i] + dot(stabX[i,:],stabZ[j,:]))%2

        end
    end
    stabX[i,:]=gX
    stabZ[i,:]=gZ
    # sign[i]=rand([0,1])

    return
end
#-------------------------------------------------
#-------------------------------------------------
function entanglement(stab,indices)
    n,=size(stab)
    return rank2!(stab[:,[indices;indices.+n]])-length(indices)
end

#-------------------------------------------------
#-------------------------------------------------
function initStabPer(n)
    stabX=zeros(Int8,n,n)
    stabZ=zeros(Int8,n,n)
    sign=zeros(Int8, n)

    #---Initializing-Stabilizers w/ periodic b.c.
    for j in 1:n
        stabX[j,mod(j-1-1,n)+1]=1
        stabZ[j,j]=1
        stabX[j,mod(j+1-1,n)+1]=1
    end


    return hcat(stabX,stabZ),sign
end
#-------------------------------------------------
#-------------------------------------------------
function initStabSPT(n)
    stabX=zeros(Int8,n,n)
    stabZ=zeros(Int8,n,n)
    sign=zeros(Int8, n)

    #---Initializing-Stabilizers
    for j in 2:n-1
        stabX[j,j-1]=1
        stabZ[j,j]=1
        stabX[j,j+1]=1
    end


    #----SPT Boundary condition
    for i in 1:n÷2
        stabZ[1,2*i]=1
        stabZ[n,2*i-1]=1
    end


    return hcat(stabX,stabZ),sign
end
#-------------------------------------------------
#-------------------------------------------------
function initStabProd(n)
    stabX=zeros(Int8, n,n)
    stabZ=Matrix{Int8}(1I,n,n)
    sign=zeros(Int8, n)

    return hcat(stabX,stabZ),sign
end
#-------------------------------------------------
#-------------------------------------------------
function initStabProd_Ancilla(n)
    stab,=initStabProd(n)
    stab=hcat(stab[:,1:n],zeros(Int8,n),stab[:,n+1:2n],zeros(Int8,n))
    stab=vcat(stab,zeros(Int8,2n+2)')
    stab[n÷2-1,2n+2]=1
    stab[n÷2+1,2n+2]=1
    stab[n+1,n÷2-1]=1
    stab[n+1,n÷2+1]=1
    stab[n+1,n+1]=1

    sign=zeros(Int8,n+1)
    return stab,sign
end
#-------------------------------------------------
#-------------------------------------------------
function z2SwapRow!(A,i,j,leftCol=1)
    if i!=j
        A[i,leftCol:end].⊻=A[j,leftCol:end]
        A[j,leftCol:end].⊻=A[i,leftCol:end]
        A[i,leftCol:end].⊻=A[j,leftCol:end]
    end
    return
end
#-------------------------------------------------
#-------------------------------------------------
function z2SwapCol!(A,i,j,topRow=1)
    if i!=j
        A[topRow:end,i].⊻=A[topRow:end,j]
        A[topRow:end,j].⊻=A[topRow:end,i]
        A[topRow:end,i].⊻=A[topRow:end,j]
    end
    return
end
#-------------------------------------------------
#-------------------------------------------------
function rank2!(A)
    m,n=size(A)
    lastPivotCol=0

    for i in 1:m
        for j in (lastPivotCol+1):n
            if A[i,j]!=0
                for jj in (j+1):n
                    if A[i,jj]!=0
                        A[i:end,jj].⊻=A[i:end,j]
                    end
                end
                z2SwapCol!(A,j,lastPivotCol+1,i)
                lastPivotCol+=1
                break
            end
        end
    end

    return lastPivotCol
end
#-------------------------------------------------
#-------------------------------------------------
function uApply3qubitUnitary!(stab,sign,u,uSign,i,j,k)
    #sign is ignored for now
    #u.T is expected

    n,=size(stab)
    stab[:,[i,j,k,i+n,j+n,k+n]]=(view(stab,:,[i,j,k,i+n,j+n,k+n])*u).%2


    return
end
#-------------------------------------------------
#-------------------------------------------------
function extendToUnitary(X_n,Z_n)
    n=length(X_n)÷2
    p_idx=pivotIdx(X_n,Z_n)

    if commute(X_n,Z_n)
        print("first vecotrs aren't anti-commuting!")
    end


    X_basis=hcat(Matrix{Int8}(1I,n,n),zeros(Int8,n,n))
    X_basis[p_idx,:]=X_n
    z2SwapRow!(X_basis,1,p_idx)

    Z_basis=hcat(zeros(Int8,n,n),Matrix{Int8}(1I,n,n))
    Z_basis[p_idx,:]=Z_n
    z2SwapRow!(Z_basis,1,p_idx)

    for i in 2:n
        #finding Zi

        #make sure Zi commutes with Xj for j<i
        for j in 1:i-1
            if !commute(Z_basis[i,:],X_basis[j,:])
                Z_basis[i,:].⊻=Z_basis[j,:]
            end
        end

        #make sure Zi commutes with Zj for j<i
        for j in 1:i-1
            if !commute(Z_basis[i,:],Z_basis[j,:])
                Z_basis[i,:].⊻=X_basis[j,:]
            end
        end


        #find an Xj that doesn't commute with Zi, name it Xi
        #first search among the remaing Xs
        foundaPair=false
        for j in i:n
            if !commute(Z_basis[i,:],X_basis[j,:])
                z2SwapRow!(X_basis,j,i)
                foundaPair=true
                break
            end
        end
        #if not found, search among the remaing Zs
        if foundaPair==false
            for j in i+1:n
                if !commute(Z_basis[i,:],Z_basis[j,:])
                    #swap the two
                    Z_basis[j,:].⊻=X_basis[i,:]
                    X_basis[i,:].⊻=Z_basis[j,:]
                    Z_basis[j,:].⊻=X_basis[i,:]
                    foundaPair=true
                    break
                end
            end
            if foundaPair==false
                println("no non-commuting partner found!")
            end
        end

        #make sure Xi commutes with Xj for j<i
        for j in 1:i-1
            if !commute(X_basis[i,:],X_basis[j,:])
                X_basis[i,:].⊻=Z_basis[j,:]
            end
        end

        #make sure Xi commutes with Zj for j<i
        for j in 1:i-1
            if !commute(X_basis[i,:],Z_basis[j,:])
                X_basis[i,:].⊻=X_basis[j,:]
            end
        end

    end

    return transpose(vcat(X_basis,Z_basis))
end

#-------------------------------------------------
#-------------------------------------------------
function pivotIdx(Sx,Sz)
    n=length(Sx)÷2
    for i in 1:n
        if !commute(Sx[[i,i+n]],Sz[[i,i+n]])
            return i
        end
    end
    return 0
end

#-------------------------------------------------
#-------------------------------------------------
function checkUnitarity(U)
    m,=size(U)
    ca=zeros(Int,m,m)
    for i in 1:m
        for j in 1:m
            ca[i,j]=commute(U[i,:],U[j,:]) ? 0 : 1
        end
    end
    return ca
end
#-------------------------------------------------
#-------------------------------------------------
function firstNZIdx(A)
    for j in eachindex(A)
        if A[j]!=0
            return j
        end
    end
    return 0
end
#-------------------------------------------------
#-------------------------------------------------
function lastNZIdx(A)
    for j in length(A):-1:1
        if A[j]!=0
            return j
        end
    end
    return 0
end
#-------------------------------------------------
#-------------------------------------------------

function commute(O1,O2)
    n=length(O1)÷2
    return (dot(O1[1:n],O2[n+1:2*n])+dot(O1[n+1:2*n],O2[1:n]))%2==0
end

#-------------------------------------------------
#-------------------------------------------------


function possibleAssignments(k)
    ns=zeros(Int8,2^k,k)
    for i in 1:2^k
        for j in 1:k
            ns[i,j]=(i÷2^(j-1))%2
        end
    end
    return ns
end
#-------------------------------------------------
#-------------------------------------------------

function generateAllCliffordUnitaries(n)
    if n==1
        Us=[]
        p=possibleAssignments(4)
        for i in 1:size(p)[1]
            if !commute(p[i,1:2],p[i,3:4])
                push!(Us,reshape(p[i,:],2,2))
            end
        end
        return Us
    else
        Us=[]
        Vs=generateAllCliffordUnitaries(n-1)
        V=zeros(Int8,2*n,2*n)
        V[1,1]=1
        V[n+1,n+1]=1
        p=possibleAssignments(4*n)
        for i in 1:size(p)[1]
            if !commute(p[i,1:2*n],p[i,2*n+1:end])
                U_prime=extendToUnitary(p[i,1:2*n],p[i,2*n+1:end])
                for v in Vs
                    V[[2:n;n+2:2*n],[2:n;n+2:2*n]]=v
                    push!(Us,(U_prime*V).%2)
                end
            end
        end
        return Us
    end
    return
end
#-------------------------------------------------
#-------------------------------------------------
function findSPTU3s()
    Us=generateAllCliffordUnitaries(3);

    SPTUs=Array{Array{Int8,2},1}(undef,768)

    Z2=zeros(Int8,6)
    Z2[5]=1

    Z1Z3=zeros(Int8,6)
    Z1Z3[[4,6]]=[1 1]

    idx=0
    for u in Us
        if u[:,5]==Z2 && (u[:,4].⊻u[:,6])==Z1Z3
            idx+=1
            SPTUs[idx]=u'
        end
    end
    println(idx," unitaries generated")
    return SPTUs

end
#-------------------------------------------------
#-------------------------------------------------
SPTU3s=findSPTU3s()
sptu3Num=length(SPTU3s)
end
