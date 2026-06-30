### RequestsManagerV2 — Access Control

These properties verify that every privileged operation in `RequestsManagerV2` is gated by the correct role or caller identity. Coverage includes admin-only config setters, service-role completion, provider/admin cancellation rights, pause mechanics, allowlist invariants, and absence of privilege escalation.

#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\ACLinkVerified}{RMV2\_AccessControl.conf}
  \item \textbf{Mitigation Run Link:} \href{\ACLinkMitig}{RMV2\_AccessControl.conf}
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

AC-1 \phantomsection \label{ac-1} & treasuryOnlyViaSetTreasuryByAdmin & treasuryAddress changes only via setTreasury; only DEFAULT\_ADMIN\_ROLE may call it. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-2 \phantomsection \label{ac-2} & allowedTokensOnlyViaAddRemoveByAdmin & allowedTokens[t] changes only via add/removeAllowedToken; only DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-3 \phantomsection \label{ac-3} & mintFeeOnlyViaSetMintFeeByAdmin & mintFee changes only via setMintFee; only DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-4 \phantomsection \label{ac-4} & burnFeeOnlyViaSetBurnFeeByAdmin & burnFee changes only via setBurnFee; only DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-5 \phantomsection \label{ac-5} & mintTTLOnlyViaSetterByAdmin & mintRequestTTL changes only via setMintRequestTTL; only DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-6 \phantomsection \label{ac-6} & burnTTLOnlyViaSetterByAdmin & burnRequestTTL changes only via setBurnRequestTTL; only DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-7 \phantomsection \label{ac-7} & burnCancelWindowOnlyViaSetterByAdmin & burnCancelWindow changes only via setBurnCancelWindow; only DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-8 \phantomsection \label{ac-8} & pauseTransitionsAuthorized & paused() toggles only via pause/unpause; PAUSER\_ROLE pauses, DEFAULT\_ADMIN\_ROLE unpauses. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-9 \phantomsection \label{ac-9} & mintCompletionRequiresService & CREATED$\rightarrow$COMPLETED for a mint request requires SERVICE\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-10 \phantomsection \label{ac-10} & burnCompletionRequiresService & CREATED$\rightarrow$COMPLETED for a burn request requires SERVICE\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-11 \phantomsection \label{ac-11} & mintCancellationRequiresProviderOrAdmin & CREATED$\rightarrow$CANCELLED for a mint request requires caller == provider or DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-12 \phantomsection \label{ac-12} & burnCancellationRequiresProviderOrAdmin & CREATED$\rightarrow$CANCELLED for a burn request requires caller == provider or DEFAULT\_ADMIN\_ROLE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-13 \phantomsection \label{ac-13} & emergencyWithdrawRequiresAdmin & only DEFAULT\_ADMIN\_ROLE can call emergencyWithdraw. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-14 \phantomsection \label{ac-14} & getRoleAdminImmutable & getRoleAdmin(role) is immutable; \_setRoleAdmin never succeeds in OZ DefaultAdminRules. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-15 \phantomsection \label{ac-15} & serviceRoleChangeAuthorized & SERVICE\_ROLE changes only via admin-gated grant/revoke or self-renounce. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-16 \phantomsection \label{ac-16} & pauserRoleChangeAuthorized & PAUSER\_ROLE changes only via admin-gated grant/revoke or self-renounce. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-17 \phantomsection \label{ac-17} & noSelfEscalationToAdmin & a non-admin caller cannot gain DEFAULT\_ADMIN\_ROLE in one call. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-18 \phantomsection \label{ac-18} & mintFeeWithinMax & mintFee $\leq$ MAX\_FEE at all times. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-19 \phantomsection \label{ac-19} & burnFeeWithinMax & burnFee $\leq$ MAX\_FEE at all times. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-20 \phantomsection \label{ac-20} & burnRequestFeeWithinMax & every existing burn request's locked fee is $\leq$ MAX\_FEE. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-21 \phantomsection \label{ac-21} & treasuryNeverZero & treasuryAddress is never the zero address. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-22 \phantomsection \label{ac-22} & issueTokenNeverAllowed & the issue token is never in the allowlist. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-23 \phantomsection \label{ac-23} & zeroAddressNeverAllowed & address(0) is never in the allowlist. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-24 \phantomsection \label{ac-24} & requestMintRevertsWhenPaused & requestMint reverts when paused. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-25 \phantomsection \label{ac-25} & requestBurnRevertsWhenPaused & requestBurn reverts when paused. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-26 \phantomsection \label{ac-26} & completeMintRevertsWhenPaused & completeMint reverts when paused. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-27 \phantomsection \label{ac-27} & completeBurnRevertsWhenPaused & completeBurn reverts when paused. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-28 \phantomsection \label{ac-28} & mintRequestTokenIsAllowed & token stored in any existing mint request is always an allowed token. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-29 \phantomsection \label{ac-29} & burnRequestTokenIsAllowed & token stored in any existing burn request is always an allowed token. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-30 \phantomsection \label{ac-30} & completeMintRejectsExpired & completeMint reverts when the request is past its TTL. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-31 \phantomsection \label{ac-31} & completeBurnRejectsExpired & completeBurn reverts when the request is past its TTL. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-32 \phantomsection \label{ac-32} & cancelBurnOnlyWithinWindow & cancelBurn (provider path) succeeds only within burnCancelWindow. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-33 \phantomsection \label{ac-33} & requestMintWithPermitSuccessSubset & requestMintWithPermit succeeds only when base requestMint preconditions hold. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-34 \phantomsection \label{ac-34} & requestBurnWithPermitSuccessSubset & requestBurnWithPermit succeeds only when base requestBurn preconditions hold. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-35 \phantomsection \label{ac-35} & allowedTokenHas18Decimals & every token in the allowlist has exactly 18 decimals. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-36 \phantomsection \label{ac-36} & cancelMintNotGatedByAllowlist & cancelMint is not gated by the allowlist; a de-allowlisted token does not block cancellation. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline
AC-37 \phantomsection \label{ac-37} & cancelBurnNotGatedByAllowlist & cancelBurn is not gated by the allowlist; a de-allowlisted token does not block cancellation. & \cellcolor{green!30}{\href{\ACLinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\ACLinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
