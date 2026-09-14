# FusionUI — our presentation layer

Renders both [OM] OpenMinis-sourced and [AA] ported views under one tab shell.
Rules (架构 v1 §3.4): only view layer goes here; any data binding must come through
RemoteKit presentation models, never AA's view-model layer (second-source ban, D4 §4).
