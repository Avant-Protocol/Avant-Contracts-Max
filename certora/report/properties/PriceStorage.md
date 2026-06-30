### PriceStorage

These properties verify the price oracle mechanics of `PriceStorage`. Coverage includes write-once per-key immutability, upward and downward band enforcement, timestamp monotonicity, `lastPrice` mirroring, service-role gating on writes, admin-only bound updates, bound range invariants, initialization correctness, and zero-key rejection.


#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\PLinkVerified}{PriceStorage.conf}
  \item \textbf{Mitigation Run Link:} \href{\PLinkMitig}{PriceStorage.conf}
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

P-1 \phantomsection \label{p-1} & priceKeyWriteOnce & Once prices[key] is written (timestamp $\neq$ 0), neither field ever changes. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-2 \phantomsection \label{p-2} & setPriceUpwardBound & lastPrice.price never exceeds prev * (1 + upperBoundPercentage / 1e18). & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-3 \phantomsection \label{p-3} & setPriceDownwardBound & lastPrice.price never falls below prev * (1 - lowerBoundPercentage / 1e18). & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-4 \phantomsection \label{p-4} & lastPriceTimestampMonotonicOnWrite & lastPrice.timestamp equals block.timestamp on every write and never decreases. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-5 \phantomsection \label{p-5} & lastPriceTimestampOnlySetPrice & Only setPrice may mutate lastPrice.timestamp. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-6 \phantomsection \label{p-6} & lastPriceMirrorsWrittenKey & After setPrice, lastPrice mirrors the key written in the same call. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-7 \phantomsection \label{p-7} & priceNonZeroWhenSet & prices[key].price is never zero once the slot is written. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-8 \phantomsection \label{p-8} & lastPriceZeroIffUnwritten & lastPrice fields are either both zero or both non-zero. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-9 \phantomsection \label{p-9} & onlyServiceRoleWritesPrice & Any mutation to prices or lastPrice requires SERVICE\_ROLE. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-10 \phantomsection \label{p-10} & onlyAdminChangesBounds & Changing upperBoundPercentage or lowerBoundPercentage requires DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-11 \phantomsection \label{p-11} & upperBoundInRange & After initialization upperBoundPercentage is in (0, 1e18]. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-12 \phantomsection \label{p-12} & lowerBoundInRange & After initialization lowerBoundPercentage is in (0, 1e18]. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-13 \phantomsection \label{p-13} & initializeAtMostOnce & initialize can only be called once; a second call always reverts. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-14 \phantomsection \label{p-14} & initializeSetsVersion & initialize sets the version to exactly 1. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-15 \phantomsection \label{p-15} & serviceRoleAdminNeverChanges & getRoleAdmin(SERVICE\_ROLE) is permanently DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-16 \phantomsection \label{p-16} & noServiceToAdminEscalation & A SERVICE\_ROLE-only caller cannot grant DEFAULT\_ADMIN\_ROLE to any account. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-17 \phantomsection \label{p-17} & lastPriceValueOnlySetPrice & lastPrice.price can only be changed by setPrice. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-18 \phantomsection \label{p-18} & firstPriceAlwaysAccepted & When no price has been written yet, setPrice accepts any non-zero price (band check is skipped). & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline
P-19 \phantomsection \label{p-19} & zeroKeyNeverSet & prices[bytes32(0)] is never written; the zero key is permanently rejected. & \cellcolor{green!30}{\href{\PLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\PLinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
