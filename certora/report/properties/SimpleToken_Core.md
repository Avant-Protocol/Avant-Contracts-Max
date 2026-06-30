### SimpleToken — Core (Idempotency \& Access Control)

These properties verify the idempotency, access control, and initialization mechanics of `SimpleToken`. Coverage includes write-once idempotency keys, key namespace isolation between mint and burn, supply change role gating, `DefaultAdminRules` coupling, permit deadline and nonce correctness, and single-initialization enforcement.

#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\STCORELinkVerified}{SimpleToken\_Core.conf}
  \item \textbf{Mitigation Run Link:} \href{\STCORELinkMitig}{SimpleToken\_Core.conf}
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

ST-CORE-1 \phantomsection \label{st-core-1} & mintIdsMonotonic & mintIds[key] once set to true is never reset. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-2 \phantomsection \label{st-core-2} & burnIdsMonotonic & burnIds[key] once set to true is never reset. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-3 \phantomsection \label{st-core-3} & keyedMintUsedKeyReverts & Keyed mint with an already-used key reverts. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-4 \phantomsection \label{st-core-4} & keyedBurnUsedKeyReverts & Keyed burn with an already-used key reverts. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-5 \phantomsection \label{st-core-5} & keyedMintOneShot & Keyed mint is one-shot: a second call with the same key always reverts. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-6 \phantomsection \label{st-core-6} & keyedBurnOneShot & Keyed burn is one-shot: a second call with the same key always reverts. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-7 \phantomsection \label{st-core-7} & keyedMintWriteIsolation & Keyed mint writes exactly its own mintIds key; no collateral writes. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-8 \phantomsection \label{st-core-8} & keyedBurnWriteIsolation & Keyed burn writes exactly its own burnIds key; no collateral writes. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-9 \phantomsection \label{st-core-9} & keyedMintDoesNotTouchBurnIds & Keyed mint never writes burnIds. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-10 \phantomsection \label{st-core-10} & keyedBurnDoesNotTouchMintIds & Keyed burn never writes mintIds. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-11 \phantomsection \label{st-core-11} & sameKeyReusableAcrossNamespaces & The same key value is independently consumable across the mint and burn namespaces. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-12 \phantomsection \label{st-core-12} & mintIdsWrittenOnlyByKeyedMint & mintIds[key] may change only via keyed mint(bytes32,address,uint256). & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-13 \phantomsection \label{st-core-13} & burnIdsWrittenOnlyByKeyedBurn & burnIds[key] may change only via keyed burn(bytes32,address,uint256). & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-14 \phantomsection \label{st-core-14} & supplyIncreaseRequiresServiceRole & totalSupply may increase only when caller holds SERVICE\_ROLE. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-15 \phantomsection \label{st-core-15} & supplyDecreaseRequiresServiceRole & totalSupply may decrease only when caller holds SERVICE\_ROLE. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-16 \phantomsection \label{st-core-16} & serviceRoleAdminNeverChanges & getRoleAdmin(SERVICE\_ROLE) is immutable; \_setRoleAdmin never succeeds. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-17 \phantomsection \label{st-core-17} & serviceRoleAdminIsDefaultAdmin & getRoleAdmin(SERVICE\_ROLE) == DEFAULT\_ADMIN\_ROLE invariant. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-18 \phantomsection \label{st-core-18} & defaultAdminRoleCoupledToSlot & hasRole(DEFAULT\_ADMIN\_ROLE, a) iff (a $\neq$ 0 and a == defaultAdmin()) OZ coupling. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-19 \phantomsection \label{st-core-19} & atMostOneDefaultAdmin & At most one DEFAULT\_ADMIN\_ROLE holder at any time. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-20 \phantomsection \label{st-core-20} & grantDefaultAdminReverts & grantRole(DEFAULT\_ADMIN\_ROLE, ...) always reverts (DefaultAdminRules). & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-21 \phantomsection \label{st-core-21} & revokeDefaultAdminReverts & revokeRole(DEFAULT\_ADMIN\_ROLE, ...) always reverts (DefaultAdminRules). & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-22 \phantomsection \label{st-core-22} & serviceRoleNoEscalation & SERVICE\_ROLE holder cannot self-escalate to DEFAULT\_ADMIN\_ROLE in one call. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-23 \phantomsection \label{st-core-23} & acceptOnlyGrantsToScheduledPendingAdmin & acceptDefaultAdminTransfer can only grant DEFAULT\_ADMIN\_ROLE to the scheduled pendingDefaultAdmin. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-24 \phantomsection \label{st-core-24} & permitRespectsDeadline & permit reverts once block.timestamp $>$ deadline. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-25 \phantomsection \label{st-core-25} & permitSuccessPostCondition & Successful permit sets allowance == value and increments nonces(owner) by exactly 1. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-26 \phantomsection \label{st-core-26} & nonceMonotonicAndOnlyPermit & nonces(owner) is monotonic non-decreasing and changes only via permit. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-27 \phantomsection \label{st-core-27} & initializeAtMostOnce & initialize is callable at most once (sequential form). & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline
ST-CORE-28 \phantomsection \label{st-core-28} & initializeRevertsWhenInitialized & initialize reverts when the contract is already initialized. & \cellcolor{green!30}{\href{\STCORELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STCORELinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
