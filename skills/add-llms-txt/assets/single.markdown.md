{{- /* Per-page markdown twin for LLMs/agents, served at <url>/index.md.
       Emits a small header (title, canonical for syndicated posts, date, tags)
       then the raw markdown body. .RawContent keeps Mermaid/shortcode source,
       which is more useful to an LLM than HTML or stripped plain text. */ -}}
# {{ .Title }}
{{ with .Params.canonicalURL }}
> Originally published at {{ . }}
{{ end }}
{{- $meta := slice -}}
{{- with .Date }}{{ $meta = $meta | append (printf "Date: %s" (.Format "2006-01-02")) }}{{ end -}}
{{- with .Params.event }}{{ $meta = $meta | append (printf "Event: %s" .) }}{{ end -}}
{{- with .Params.tags }}{{ $meta = $meta | append (printf "Tags: %s" (delimit . ", ")) }}{{ end -}}
{{- with $meta }}
{{ delimit . " · " }}
{{ end }}
{{ .RawContent }}
