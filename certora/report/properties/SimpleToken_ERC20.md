### SimpleToken — ERC-20

These properties verify the standard ERC-20 behavior of `SimpleToken`. Coverage includes the sum-of-balances invariant, supply change attribution, per-account balance bound, transfer and `transferFrom` conservation, self-transfer identity, allowance decrement, zero-address rejection, and correct mint/burn effects for both keyed and keyless overloads.

#### Run Link

\small
\begin{itemize}
  \item \textbf{Audit Run Link:} \href{\STELinkVerified}{SimpleToken\_ERC20.conf}
  \item \textbf{Mitigation Run Link:} \href{\STELinkMitig}{SimpleToken\_ERC20.conf}
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

ST-ERC20-1 \phantomsection \label{st-erc20-1} & totalSupplyIsSumOfBalances & sum(balanceOf) == totalSupply at every reachable state. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-2 \phantomsection \label{st-erc20-2} & totalSupplyChangesOnlyViaMintBurn & totalSupply changes only via the four mint/burn overloads. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-3 \phantomsection \label{st-erc20-3} & balanceLeTotalSupply & balanceOf(a) $\leq$ totalSupply for every account. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-4 \phantomsection \label{st-erc20-4} & transferConservesSupply & transfer conserves totalSupply and moves exactly amt from sender to receiver. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-5 \phantomsection \label{st-erc20-5} & transferFromConservesSupply & transferFrom conserves totalSupply and moves exactly amt from/to. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-6 \phantomsection \label{st-erc20-6} & selfTransferIdentity & Self-transfer leaves sender balance unchanged. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-7 \phantomsection \label{st-erc20-7} & transferFromDecrementsAllowance & transferFrom decrements allowance by amt unless infinite approval. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-8 \phantomsection \label{st-erc20-8} & transferRejectsZeroAddress & transfer reverts when to or from is the zero address. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-9 \phantomsection \label{st-erc20-9} & transferFromRejectsZeroAddress & transferFrom reverts when from or to is the zero address. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-10 \phantomsection \label{st-erc20-10} & keylessMintEffect & Keyless mint raises balanceOf(account) and totalSupply each by amt; reverts if account == 0. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-11 \phantomsection \label{st-erc20-11} & keyedMintEffect & Keyed mint raises balanceOf(account) and totalSupply each by amt; reverts if account == 0. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-12 \phantomsection \label{st-erc20-12} & keylessBurnEffect & Keyless burn lowers balanceOf(account) and totalSupply each by amt; reverts if account == 0. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-13 \phantomsection \label{st-erc20-13} & keyedBurnEffect & Keyed burn lowers balanceOf(account) and totalSupply each by amt; reverts if account == 0. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline
ST-ERC20-14 \phantomsection \label{st-erc20-14} & burnRejectsInsufficientBalance & burn reverts when account == 0 or amt $>$ balance. & \cellcolor{green!30}{\href{\STELinkVerified}{\checkmark}} & \cellcolor{green!30}{\href{\STELinkMitig}{\checkmark}} &  \\ \hline

\end{longtable}
\end{center}
\end{scriptsize}
