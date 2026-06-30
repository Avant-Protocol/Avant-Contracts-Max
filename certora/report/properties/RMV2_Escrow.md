### RequestsManagerV2 — Escrow

These properties verify the token-flow integrity of `RequestsManagerV2`. Coverage includes settlement conservation for mint and burn, exact inflow on deposit, native ETH cannot accumulate, treasury protection for non-allowlisted tokens, zero-address token balance safety, full refund on all cancellation paths, and the emergencyWithdraw rug-path consequences: once the deposit token is drained, `completeMint`, `cancelMint`, and `adminCancelMint` all revert; once the issue token is drained, `completeBurn`, `cancelBurn`, and `adminCancelBurn` all revert — making escrowed funds irrecoverable through any path on both sides.

#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\ELinkVerified}{RMV2\_Escrow.conf}
  \item \textbf{Mitigation Run Link:} \href{\ELinkMitig}{RMV2\_Escrow.conf}
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

E-1 \phantomsection \label{e-1} & mintEscrowBacked & Per-deposit-token escrow backing lower bound. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-2 \phantomsection \label{e-2} & burnEscrowBacked & Issue-token escrow backing lower bound. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-3 \phantomsection \label{e-3} & completeMint\_settlementConservation & completeMint sends exactly request.amount deposit token to treasury and mints exactly mintAmount to provider. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-4 \phantomsection \label{e-4} & completeBurn\_settlementConservation & completeBurn burns exactly request.amount issue token and sends exactly withdrawalAmount from treasury to provider. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-5 \phantomsection \label{e-5} & requestMintInflowIntegrity & requestMint pulls in exactly request.amount of the deposit token (non-FoT token). & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-6 \phantomsection \label{e-6} & requestBurnInflowIntegrity & requestBurn pulls in exactly request.amount of the issue token. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-7 \phantomsection \label{e-7} & noNativeEthStuck & Manager native ETH balance stays 0 across any call. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-8 \phantomsection \label{e-8} & requestMintRevertsWhenInsufficientBalance & requestMint reverts when amount exceeds the provider's deposit-token balance. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-9 \phantomsection \label{e-9} & onlyMsgSenderBalanceCanDecrease & No RMV2 call may decrease a third party's tokenA balance; only msg.sender's balance can decrease. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-10 \phantomsection \label{e-10} & requestBurnRevertsWhenInsufficientBalance & requestBurn reverts when amount exceeds the provider's issue-token balance. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-11 \phantomsection \label{e-11} & onlyMsgSenderIssueTokenBalanceCanDecrease & No RMV2 call may decrease a third party's issue-token balance; only msg.sender's balance can decrease. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-12 \phantomsection \label{e-12} & zeroAddressHoldsNoIssueToken & address(0) never holds any issue token. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-13 \phantomsection \label{e-13} & zeroAddressHoldsNoTokenA & address(0) never holds any tokenA. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-14 \phantomsection \label{e-14} & treasuryNonAllowedTokenBalancePersists & Treasury balance of a non-allowlisted token never changes. & \cellcolor{red!30}{\href{\ELinkViolated}{$\times$}} & \cellcolor{yellow!30}{ACK} & \hyperref[l-01]{L-01}, ACK\\ \hline
E-15 \phantomsection \label{e-15} & treasuryTokenAUnchangedIfPriceZero & Treasury's tokenA balance cannot change when the oracle price is zero. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-16 \phantomsection \label{e-16} & cancelMintFullRefund & cancelMint refunds exactly request.amount to the provider, no fee haircut. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-17 \phantomsection \label{e-17} & adminCancelMintFullRefund & adminCancelMint refunds exactly request.amount to the provider, no fee haircut. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-18 \phantomsection \label{e-18} & cancelBurnFullRefund & cancelBurn refunds exactly request.amount of issue token to the provider, no fee haircut. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-19 \phantomsection \label{e-19} & adminCancelBurnFullRefund & adminCancelBurn refunds exactly request.amount of issue token to the provider, no fee haircut. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-20 \phantomsection \label{e-20} & completeMintRevertsAfterEmergencyWithdraw & completeMint reverts after emergencyWithdraw drains the deposit token; the rug path makes settlement impossible. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-21 \phantomsection \label{e-21} & cancelMintRevertsAfterEmergencyWithdraw & cancelMint reverts after emergencyWithdraw drains the deposit token; providers cannot recover escrowed funds. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-22 \phantomsection \label{e-22} & adminCancelMintRevertsAfterEmergencyWithdraw & adminCancelMint reverts after emergencyWithdraw drains the deposit token; even the admin cancel path cannot return escrowed funds. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-23 \phantomsection \label{e-23} & emergencyWithdrawDrainsFullBalance & emergencyWithdraw leaves exactly zero deposit token balance in the contract; the entire balance is transferred to the admin caller. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-24 \phantomsection \label{e-24} & completeBurnRevertsAfterEmergencyWithdrawIssueToken & completeBurn reverts after emergencyWithdraw drains the issue token; the burn-escrow rug path makes settlement impossible. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-25 \phantomsection \label{e-25} & cancelBurnRevertsAfterEmergencyWithdrawIssueToken & cancelBurn reverts after emergencyWithdraw drains the issue token; providers cannot recover escrowed issue tokens. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline
E-26 \phantomsection \label{e-26} & adminCancelBurnRevertsAfterEmergencyWithdrawIssueToken & adminCancelBurn reverts after emergencyWithdraw drains the issue token; even the admin cancel path cannot return escrowed issue tokens. & \cellcolor{green!30}{\href{\ELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ELinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
