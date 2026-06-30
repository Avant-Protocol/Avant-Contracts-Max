### RequestsManagerV2 — State Machine

These properties verify the request lifecycle state machine. Coverage includes terminal-state absorption (COMPLETED/CANCELLED are absorbing), transitions only out of CREATED, wrong-state rejection, CEI ordering (state written before any token transfer), pause-independence of admin cancel paths, prevention of double-settlement, and TTL-independence of provider cancel paths (both `cancelMint` and `cancelBurn` remain available after TTL expiry).

#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\SMLinkVerified}{RMV2\_StateMachine.conf}
  \item \textbf{Mitigation Run Link:} \href{\SMLinkMitig}{RMV2\_StateMachine.conf}
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

SM-1 \phantomsection \label{sm-1} & mintTerminalAbsorption & COMPLETED/CANCELLED mint request stays in that terminal state forever. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-2 \phantomsection \label{sm-2} & burnTerminalAbsorption & COMPLETED/CANCELLED burn request stays in that terminal state forever. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-3 \phantomsection \label{sm-3} & mintTransitionsOnlyFromCreated & A mint request can only transition out of CREATED. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-4 \phantomsection \label{sm-4} & burnTransitionsOnlyFromCreated & A burn request can only transition out of CREATED. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-5 \phantomsection \label{sm-5} & mintWrongStateReverts & completeMint/cancelMint/adminCancelMint revert when not CREATED. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-6 \phantomsection \label{sm-6} & burnWrongStateReverts & completeBurn/cancelBurn/adminCancelBurn revert when not CREATED. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-7 \phantomsection \label{sm-7} & mintCEIStateBeforeTransfer\_complete & CEI: completeMint writes state before any transfer. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-8 \phantomsection \label{sm-8} & mintCEIStateBeforeTransfer\_cancel & CEI: cancelMint writes state before any transfer. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-9 \phantomsection \label{sm-9} & mintCEIStateBeforeTransfer\_adminCancel & CEI: adminCancelMint writes state before any transfer. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-10 \phantomsection \label{sm-10} & burnCEIStateBeforeTransfer\_complete & CEI: completeBurn writes state before any transfer. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-11 \phantomsection \label{sm-11} & burnCEIStateBeforeTransfer\_cancel & CEI: cancelBurn writes state before any transfer. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-12 \phantomsection \label{sm-12} & burnCEIStateBeforeTransfer\_adminCancel & CEI: adminCancelBurn writes state before any transfer. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-13 \phantomsection \label{sm-13} & adminCancelMintPauseIndependent & adminCancelMint does not revert due to pause state. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-14 \phantomsection \label{sm-14} & adminCancelBurnPauseIndependent & adminCancelBurn does not revert due to pause state. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-15 \phantomsection \label{sm-15} & G\_emergencyWithdrawStateInert & emergencyWithdraw does not touch any request state or field. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-16 \phantomsection \label{sm-16} & adminCancelBurnIgnoresCancelWindow & adminCancelBurn ignores burnCancelWindow; admin can cancel even after the window has elapsed. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-17 \phantomsection \label{sm-17} & cancelMintTTLIndependent & cancelMint is not gated by mintRequestTTL; provider can cancel a CREATED mint even after TTL has elapsed. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-18 \phantomsection \label{sm-18} & cancelBurnTTLIndependent & cancelBurn is not gated by burnRequestTTL; provider can cancel a CREATED burn within the cancel window even after TTL has elapsed. & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-19 \phantomsection \label{sm-19} & noDoubleCompleteMint & A second completeMint for the same id always reverts (COMPLETED is terminal). & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline
SM-20 \phantomsection \label{sm-20} & noDoubleCompleteBurn & A second completeBurn for the same id always reverts (COMPLETED is terminal). & \cellcolor{green!30}{\href{\SMLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\SMLinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
