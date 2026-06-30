### RequestsManagerV2 — Settlement Mathematics

These properties verify the settlement mathematics for mint and burn operations. Coverage includes anti-inflation ceilings, protocol-favoring truncation, fee and price monotonicity, intermediate overflow safety, supply change attribution, dust-revert behavior, and no-free-value guarantees.

#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\SLinkVerified}{RMV2\_Settlement.conf}
  \item \textbf{Mitigation Run Link:} \href{\SLinkMitig}{RMV2\_Settlement.conf}
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

S-1 \phantomsection \label{s-1} & mintPreFeeBound & Pre-fee anti-inflation ceiling: post-fee mint amount $\leq$ deposit*PRECISION/price. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-2 \phantomsection \label{s-2} & mintRoundsDownTowardProtocol & Mint rounding always favors the protocol (user gets floor). & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-3 \phantomsection \label{s-3} & burnRoundsDownTowardProtocol & Burn rounding always favors the protocol (user gets floor). & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-4 \phantomsection \label{s-4} & mintFeeMonotonic & Mint output is monotone non-increasing in fee. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-5 \phantomsection \label{s-5} & mintPriceMonotonic & Mint output is monotone non-increasing in price. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-6 \phantomsection \label{s-6} & burnFeeMonotonic & Burn output is monotone non-increasing in fee. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-7 \phantomsection \label{s-7} & burnPriceMonotonic & Burn output is monotone non-decreasing in price. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-8 \phantomsection \label{s-8} & mintIntermediatesFitUint256 & Mint intermediates fit uint256; (PRECISION - fee) never underflows. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-9 \phantomsection \label{s-9} & burnIntermediatesFitUint256 & Burn intermediates fit uint256; (PRECISION - fee) never underflows. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-10 \phantomsection \label{s-10} & completeMint\_antiInflation & completeMint raises totalSupply by exactly the computed amount, bounded by the anti-inflation ceiling. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-11 \phantomsection \label{s-11} & onlyCompleteMintIncreasesSupply & Only completeMint may increase the issue-token totalSupply. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-12 \phantomsection \label{s-12} & onlyCompleteBurnDecreasesSupply & Only completeBurn may decrease the issue-token totalSupply. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-13 \phantomsection \label{s-13} & completeBurn\_settlement & completeBurn value conservation: exact settlement at min(locked,current) price. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-14 \phantomsection \label{s-14} & completeMint\_zeroOut\_revertsPreservesState & Mint dust rounds to zero =$>$ revert ZeroAmountOut, state stays CREATED. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-15 \phantomsection \label{s-15} & completeBurn\_zeroOut\_revertsPreservesState & Burn dust rounds to zero =$>$ revert ZeroAmountOut, state stays CREATED. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-16 \phantomsection \label{s-16} & noFreeMint & No free value: non-zero mint output requires non-zero deposit. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline
S-17 \phantomsection \label{s-17} & noFreeBurn & No free value: non-zero burn output requires non-zero amount. & \cellcolor{green!30}{\href{\SLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SLinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
