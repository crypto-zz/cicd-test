pragma solidity ^0.5.16;

interface AdminOwnerInterface {
  function admin() external view returns(address);
  function owner() external view returns(address);
}