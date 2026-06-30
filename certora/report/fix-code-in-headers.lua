-- fix-code-in-headers.lua
-- Replaces inline code spans inside headings with \texttt{} for LaTeX output.
-- \Verb (used by fvextra) cannot appear inside moving arguments (headings,
-- TOC entries, PDF bookmarks), causing "\FVExtraUnexpandedReadStarOArgBVArg
-- has an extra }" errors.  \texttt is robust everywhere.

function Header(h)
    if not FORMAT:match 'latex' then return end
    h.content = h.content:walk({
        Code = function(el)
            -- escape special LaTeX chars that can appear in code identifiers
            local text = el.text
                :gsub('\\', '\\textbackslash{}')
                :gsub('{',  '\\{')
                :gsub('}',  '\\}')
                :gsub('_',  '\\_')
                :gsub('%^', '\\^{}')
                :gsub('&',  '\\&')
                :gsub('#',  '\\#')
                :gsub('%$', '\\$')
                :gsub('%%', '\\%%')
                :gsub('~',  '\\textasciitilde{}')
            return pandoc.RawInline('latex', '\\texttt{' .. text .. '}')
        end
    })
    return h
end
