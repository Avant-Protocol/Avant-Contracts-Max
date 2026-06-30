### RequestsManagerV2 — Structural

These properties verify the structural integrity of request storage. Coverage includes monotonic and bounded counters, fresh-slot guarantee (no id reuse), write-targeting of `requestMint`/`requestBurn`, field immutability after creation, non-existent-request revert, V1/V2 id-space separation via `INITIAL_COUNTER`, and fee-isolation on `setBurnFee`.

#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\STRUCTLinkVerified}{RMV2\_Structural.conf}
  \item \textbf{Mitigation Run Link:} \href{\STRUCTLinkMitig}{RMV2\_Structural.conf}
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

STR-1 \phantomsection \label{str-1} & mintCounterMonotonic & mintRequestsCounter never decreases and increases by at most 1 per call. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-2 \phantomsection \label{str-2} & burnCounterMonotonic & burnRequestsCounter never decreases and increases by at most 1 per call. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-3 \phantomsection \label{str-3} & mintFreshSlot & Any id $\geq$ mintRequestsCounter has an empty slot (no mint id reuse). & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-4 \phantomsection \label{str-4} & burnFreshSlot & Any id $\geq$ burnRequestsCounter has an empty slot (no burn id reuse). & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-5 \phantomsection \label{str-5} & requestMintWriteTargeting & requestMint writes only the pre-call counter slot, sets it CREATED/msg.sender, increments counter by one, touches no other id. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-6 \phantomsection \label{str-6} & requestBurnWriteTargeting & requestBurn writes only the pre-call counter slot, sets it CREATED/msg.sender, increments counter by one, touches no other id. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-7 \phantomsection \label{str-7} & mintFieldImmutability & provider/createdAt/token/amount of a mint request are fixed after creation; only state may change. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-8 \phantomsection \label{str-8} & burnFieldImmutability & provider/createdAt/token/amount/price/fee of a burn request are fixed after creation; only state may change. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-9 \phantomsection \label{str-9} & mintNonExistentRequestReverts & completeMint/cancelMint/adminCancelMint revert when the mint request does not exist (provider == 0). & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-10 \phantomsection \label{str-10} & burnNonExistentRequestReverts & completeBurn/cancelBurn/adminCancelBurn revert when the burn request does not exist (provider == 0). & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-11 \phantomsection \label{str-11} & mintCounterAtLeastInitial & mintRequestsCounter never falls below INITIAL\_COUNTER, preserving V1 id-separation. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-12 \phantomsection \label{str-12} & burnCounterAtLeastInitial & burnRequestsCounter never falls below INITIAL\_COUNTER, preserving V1 id-separation. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-13 \phantomsection \label{str-13} & mintRequestAmountNonZero & Every existing mint request (provider $\neq$ 0) has a non-zero amount. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-14 \phantomsection \label{str-14} & burnRequestAmountNonZero & Every existing burn request (provider $\neq$ 0) has a non-zero amount. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-15 \phantomsection \label{str-15} & immutablesNeverChange & ISSUE\_TOKEN\_ADDRESS never changes after construction. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-16 \phantomsection \label{str-16} & priceStorageImmutable & PRICE\_STORAGE never changes after construction. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline
STR-17 \phantomsection \label{str-17} & setBurnFeeDoesNotTouchPendingBurns & setBurnFee does not mutate locked fees of already-created burn requests. & \cellcolor{green!30}{\href{\STRUCTLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STRUCTLinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
