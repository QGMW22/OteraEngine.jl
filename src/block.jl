struct JLCodeBlock
    code::String
end

mutable struct SuperBlock
    count::Int
end

struct VariableBlock
    exp::String
end

struct TmpStatement
    st::String
end

struct TmpBlock
    name::String
    contents::Vector{Union{String, VariableBlock, TmpStatement, SuperBlock}}
end

function Base.push!(a::TmpBlock, v::Union{String, VariableBlock, TmpStatement, SuperBlock})
    push!(a.contents, v)
end

function (TB::TmpBlock)(filters::Dict{String, Symbol}, autoescape::Bool)
    code = ""
    for content in TB.contents
        t = typeof(content)
        if isa(content, TmpStatement)
            code *= "$(content.st);"
        elseif isa(content, VariableBlock)
            if occursin("|>", content.exp)
                exp = map(strip, split(content.exp, "|>"))
                f = filters[exp[2]]
                if autoescape && f != htmlesc
                    code *= "txt *= htmlesc($(string(f))(string($(content.exp))));"
                else
                    code *= "txt *= $(string(f))(string($(content.exp)));"
                end
            else
                if autoescape
                    code *= "txt *= htmlesc(string($(content.exp)));"
                else
                    code *= "txt *= string($(content.exp));"
                end
            end
        elseif isa(content, String)
            code *= "txt *= \"$(replace(content, "\""=>"\\\""))\";"
        end
    end
    return code
end

struct TmpCodeBlock
    contents::Vector{Union{String, VariableBlock, TmpStatement, TmpBlock}}
end

function (TCB::TmpCodeBlock)(filters::Dict{String, Symbol}, autoescape::Bool)
    code = ""
    for content in TCB.contents
        if isa(content, TmpStatement)
            code *= "$(content.st);"
        elseif isa(content, TmpBlock)
            code *= content(filters, autoescape)
        elseif isa(content, VariableBlock)
            if occursin("|>", content.exp)
                exp = map(strip, split(content.exp, "|>"))
                f = filters[exp[2]]
                if autoescape && f != htmlesc
                    code *= "txt *= htmlesc($(string(f))(string($(content.exp))));"
                else
                    code *= "txt *= $(string(f))(string($(content.exp)));"
                end
            else
                if autoescape
                    code *= "txt *= htmlesc(string($(content.exp)));"
                else
                    code *= "txt *= string($(content.exp));"
                end
            end
        elseif isa(content, String)
            code *= "txt *= \"$(replace(content, "\""=>"\\\""))\";"
        end
    end
    expr = Meta.parse(code)
    if expr.head == :toplevel
        return Expr(:block, expr.args...)
    else
        return expr
    end
end

CodeBlockVector = Vector{Union{String, JLCodeBlock, TmpCodeBlock, TmpBlock, VariableBlock, SuperBlock}}
SubCodeBlockVector = Vector{Union{String, JLCodeBlock, TmpStatement, TmpBlock, VariableBlock, SuperBlock}}

function get_string(tb::TmpBlock)
    txt = ""
    for content in tb.contents
        if typeof(content) == String
            txt *= content
        end
    end
    return txt
end

function process_super(child::TmpBlock, parent::TmpBlock)
    for i in 1 : length(child.contents)
        if typeof(child.contents[i]) == SuperBlock
            child.contents[i].count -= 1
            if child.contents[i].count == 0
                child.contents[i] = get_string(parent)
            end
        end
    end
    return child
end

function inherite_blocks(src::Vector{TmpBlock}, dst::Vector{TmpBlock})
    for i in 1 : length(src)
        idx = findfirst(x->x.name==src[i].name, dst)
        if idx === nothing
            push!(dst, src[i])
        else
            dst[idx] = process_super(src[i], dst[idx])
        end
    end
    return dst
end

function apply_inheritance(elements::CodeBlockVector, blocks::Vector{TmpBlock})
    for i in eachindex(elements)
        if typeof(elements[i]) == TmpCodeBlock
            idxs = findall(x->typeof(x)==TmpBlock, elements[i].contents)
            length(idxs) == 0 && continue
            for j in idxs
                idx = findfirst(x->x.name==elements[i].contents[j].name, blocks)
                if idx === nothing
                    elements[i].contents[j] = ""
                else
                    elements[i].contents[j] = blocks[idx]
                end
            end
        end
    end
    return elements
end