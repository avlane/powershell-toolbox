function Get-PtWaitDescription {
    <#
    .SYNOPSIS
    Returns a one-line explanation of a common SQL Server wait type.

    .DESCRIPTION
    A short reminder of what a wait usually means and where to look first. Wait
    types that are not in the list return an empty string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$WaitType
    )

    switch -Regex ($WaitType) {
        '^CXPACKET$'                { return 'Parallel query threads waiting for each other. Look at MAXDOP, the cost threshold for parallelism, statistics and skewed data.' }
        '^CXCONSUMER$'              { return 'A parallel consumer thread waiting for rows. Usually harmless on its own.' }
        '^SOS_SCHEDULER_YIELD$'     { return 'Queries used their CPU time slice and went back in the queue. CPU pressure, or expensive scans.' }
        '^THREADPOOL$'              { return 'No worker thread available. Blocking chains, or too many concurrent requests.' }
        '^RESOURCE_SEMAPHORE$'      { return 'Queries wait for a memory grant. Look at large sorts and hashes, bad estimates and max server memory.' }
        '^PAGEIOLATCH_'             { return 'Waiting for a data page to be read from disk. Slow storage, missing indexes, or too little memory.' }
        '^PAGELATCH_'               { return 'Contention on a page in memory (often tempdb allocation pages or a hot insert page).' }
        '^LATCH_'                   { return 'Contention on an internal structure; check sys.dm_os_latch_stats.' }
        '^WRITELOG$'                { return 'Waiting for the transaction log to be hardened to disk. Log disk latency, or many tiny commits.' }
        '^LOGBUFFER$'               { return 'Waiting for space in the log buffer; the log disk cannot keep up.' }
        '^LCK_M_'                   { return 'Waiting for a lock held by another session. See Get-PtBlockingSession.' }
        '^ASYNC_NETWORK_IO$'        { return 'The client is slow to consume the result set, or the network is. Often an application row-by-row loop.' }
        '^HADR_SYNC_COMMIT$'        { return 'Synchronous availability group commit waiting for the secondary to harden the log.' }
        '^IO_COMPLETION$'           { return 'Waiting for non-data I/O, such as sort spills or reading the transaction log.' }
        '^ASYNC_IO_COMPLETION$'     { return 'Waiting for asynchronous I/O such as backups and restores.' }
        '^BACKUPIO$|^BACKUPBUFFER$' { return 'Backup waiting on the backup target or the source disks.' }
        '^WRITE_COMPLETION$'        { return 'Waiting for a write to finish, for example checkpoint or log-related writes.' }
        '^CMEMTHREAD$'              { return 'Contention on a shared memory object; often many concurrent compiles.' }
        '^OLEDB$'                   { return 'Waiting for an OLE DB call, such as a linked server query or DBCC CHECKDB.' }
        '^SOS_WORK_DISPATCHER$'     { return 'Idle worker waiting for work; benign.' }
        default                     { return '' }
    }
}
