module github.com/nczempin/httpc-go-uring

go 1.22.2

require (
	github.com/godzie44/go-uring v0.0.0-20250501163612-d16a9e597639
	github.com/iceber/iouring-go v0.0.0-20230403020409-002cfd2e2a90
)

require (
	github.com/libp2p/go-sockaddr v0.1.1 // indirect
	golang.org/x/sys v0.0.0-20210921065528-437939a70204 // indirect
)

replace github.com/godzie44/go-uring/uring => github.com/godzie44/go-uring v0.0.0-20250501163612-d16a9e597639
