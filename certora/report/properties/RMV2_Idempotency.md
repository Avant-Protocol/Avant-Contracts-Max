### RequestsManagerV2 — Idempotency Keys

These properties verify that the on-chain idempotency keys used by `completeMint` and `completeBurn` are collision-free. Coverage includes injectivity of mint and burn key derivation, disjointness between mint and burn namespaces, and separation from V1 legacy keys by both tag byte and preimage length.

#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\IDPLinkVerified}{RMV2\_Idempotency.conf}
  \item \textbf{Mitigation Run Link:} \href{\IDPLinkMitig}{RMV2\_Idempotency.conf}
\end{itemize}

#### Properties

\begin{scriptsize}
\renewcommand{\arraystretch}{1.2}
\begin{center}

\begin{longtable}{|l|l|p{5cm}|c|c|p{1cm}|}
\hline
\rowcolor[HTML]{E6E6E6}
\textbf{Code} & \textbf{Name} & \textbf{Description} & \textbf{Audit} & \textbf{Mitig} & \textbf{Issues} \\ \hline
\endfirsthead

\hline
\rowcolor[HTML]{E6E6E6}
\textbf{Code} & \textbf{Name} & \textbf{Description} & \textbf{Audit} & \textbf{Mitig} & \textbf{Issues} \\ \hline
\endhead

IDP-1 \phantomsection \label{idp-1} & mintKeyInjective & keyMint is injective over ids: i != j => keyMint(i) != keyMint(j). & \cellcolor{green!30}{\href{\IDPLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\IDPLinkMitig}{\checkmark}} &  \\ \hline
IDP-2 \phantomsection \label{idp-2} & burnKeyInjective & keyBurn is injective over ids: i != j => keyBurn(i) != keyBurn(j). & \cellcolor{green!30}{\href{\IDPLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\IDPLinkMitig}{\checkmark}} &  \\ \hline
IDP-3 \phantomsection \label{idp-3} & mintBurnKeyDisjoint & Mint and burn V2 keys are disjoint: no keyMint(i) equals any keyBurn(j). & \cellcolor{green!30}{\href{\IDPLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\IDPLinkMitig}{\checkmark}} &  \\ \hline
IDP-4 \phantomsection \label{idp-4} & v2DisjointFromLegacy\_byTagCase & V2 lowercase tags ('m'/'b') differ from legacy uppercase ('M'/'B') at every id. & \cellcolor{green!30}{\href{\IDPLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\IDPLinkMitig}{\checkmark}} &  \\ \hline
IDP-5 \phantomsection \label{idp-5} & v2DisjointFromLegacy\_byLength & V2 preimage is exactly 36 bytes; legacy is strictly longer due to non-empty product prefix. & \cellcolor{green!30}{\href{\IDPLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\IDPLinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
