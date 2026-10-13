## Language selection and dispatch for syntax highlighting.
import Css
import Html
import Syntax

Highlight := [].{
	Language : [HtmlLanguage, CssLanguage, PlainText]

	language_for : Str -> Language
	language_for = detect_language

	display_name : Language -> Str
	display_name = language_name

	highlight : Language, Str -> List(Syntax.HighlightSpan)
	highlight = highlight_source
}

detect_language : Str -> Highlight.Language
detect_language = |path| {
	lower = path.with_ascii_lowercased()
	if lower.ends_with(".html") or lower.ends_with(".htm") {
		HtmlLanguage
	} else if lower.ends_with(".css") {
		CssLanguage
	} else {
		PlainText
	}
}

language_name : Highlight.Language -> Str
language_name = |language| match language {
	HtmlLanguage => "HTML"
	CssLanguage => "CSS"
	PlainText => "PLAIN TEXT"
}

highlight_source : Highlight.Language, Str -> List(Syntax.HighlightSpan)
highlight_source = |language, source| match language {
	HtmlLanguage => Html.highlight(source)
	CssLanguage => Css.highlight(source)
	PlainText => []
}

expect Highlight.language_for("INDEX.HTML") == HtmlLanguage
expect Highlight.language_for("assets/site.css") == CssLanguage
expect Highlight.language_for("notes.txt") == PlainText
expect Highlight.display_name(CssLanguage) == "CSS"
expect Highlight.highlight(PlainText, "plain").is_empty()
