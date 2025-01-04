// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISP } from "@ethsign/sign-protocol-evm/src/interfaces/ISP.sol";
import { Attestation } from "@ethsign/sign-protocol-evm/src/models/Attestation.sol";
import { DataLocation } from "@ethsign/sign-protocol-evm/src/models/DataLocation.sol";

enum AttestationStatus { NotInitiated, Pending, Signed, Rejected }
enum EmployerStatus { Unregistered, Registered }

contract Employd is Ownable, ReentrancyGuard {

    struct ExperienceInput {
        string role;
        string seekerName;
        string seekerEnsName;
        string employerName;
        string employerEnsName;
        string startMonth;
        string startYear;
        string endMonth;
        string endYear;
        string employmentType;
        string description;
        address employerAddress;
        string employerEmail;
    }

    struct Experience {
        uint32 id;
        address owner;
        string role;
        string seekerName;
        string seekerEnsName;
        string employerName;
        string employerEnsName;
        string startMonth;
        string startYear;
        string endMonth;
        string endYear;
        string employmentType;
        string description;
        address employerAddress;
        address seekerAddress;
        AttestationStatus attestationStatus;
        EmployerStatus employerStatus;
        string employerEmail;  // Used only for unregistered employers
    }

    mapping(uint32 => Experience) private experiences;
    mapping(address => uint32[]) private userExperienceIds;
    mapping(address => uint32[]) private employerExperienceIds;
    mapping(string => address) private employerEmailToAddress;
    mapping(string => uint32[]) private employerEmailExperiences;
    uint32 private nextId = 1;

    ISP private spInstance;
    uint64 private schemaId;

    event ExperienceAdded(uint32 indexed experienceId, address indexed owner, EmployerStatus employerStatus);
    event EmployerChosen(uint32 indexed experienceId, address indexed employerAddress, string employerEns);
    event EmployerRegistered(uint32 indexed experienceId, address indexed employerAddress, string employerEnsName);
    event AttestationSigned(uint32 indexed experienceId, address indexed seeker, address indexed employer, uint64 attestationId);
    event AttestationRejected(uint32 indexed experienceId);

    modifier validExperienceId(uint32 experienceId) {
        require(experiences[experienceId].id != 0, "Experience does not exist");
        _;
    }

    function setSPInstance(address instance) external onlyOwner {
        spInstance = ISP(instance);
    }

    function setSchemaID(uint64 schemaId_) external onlyOwner {
        schemaId = schemaId_;
    }

    function addExperience(ExperienceInput memory input) external nonReentrant returns (uint32) {
        require(bytes(input.role).length > 0, "Role cannot be empty");
        require(bytes(input.seekerEnsName).length > 0, "Seeker ENS cannot be empty");
        require(bytes(input.employerName).length > 0, "Employer name required");

        EmployerStatus employerStatus;

        if (input.employerAddress != address(0)) {
            require(bytes(input.employerEnsName).length > 0, "Employer ENS required");
            employerStatus = EmployerStatus.Registered;
        } else {
            require(bytes(input.employerEmail).length > 0, "Email required");
            employerStatus = EmployerStatus.Unregistered;
        }

        uint32 id = nextId++;
        experiences[id] = Experience({
            id: id,
            owner: msg.sender,
            role: input.role,
            seekerName: input.seekerName,
            seekerEnsName: input.seekerEnsName,
            employerName: input.employerName,
            employerEnsName: input.employerEnsName,
            startMonth: input.startMonth,
            startYear: input.startYear,
            endMonth: input.endMonth,
            endYear: input.endYear,
            employmentType: input.employmentType,
            description: input.description,
            employerAddress: input.employerAddress,
            seekerAddress: msg.sender,
            attestationStatus: AttestationStatus.NotInitiated,
            employerStatus: employerStatus,
            employerEmail: input.employerEmail
        });

        userExperienceIds[msg.sender].push(id);
        
        if (employerStatus == EmployerStatus.Unregistered) {
            employerEmailExperiences[input.employerEmail].push(id);
        }

        emit ExperienceAdded(id, msg.sender, employerStatus);
        return id;
    }

    function chooseEmployerForAttestation(uint32 experienceId, address employerAddress)
        external
        validExperienceId(experienceId)
        nonReentrant {
        Experience storage experience = experiences[experienceId];
        require(msg.sender == experience.owner, "Only the experience owner can assign employer");
        require(employerAddress != address(0), "Invalid employer address");
        require(experience.attestationStatus == AttestationStatus.NotInitiated, "Attestation already initiated");

        experience.employerAddress = employerAddress;
        experience.attestationStatus = AttestationStatus.Pending;
        employerExperienceIds[employerAddress].push(experienceId);

        emit EmployerChosen(experienceId, employerAddress, experience.employerEnsName);
    }

    function assignEmployerToExperience(
        uint32 experienceId, 
        address employerAddress,
        string memory employerEnsName
    ) external validExperienceId(experienceId) nonReentrant {
        Experience storage experience = experiences[experienceId];
        require(experience.employerStatus == EmployerStatus.Unregistered, "Employer already registered");
        require(employerAddress != address(0), "Invalid employer address");
        require(bytes(employerEnsName).length > 0, "Employer ENS name required");
        require(bytes(experience.employerEmail).length > 0, "No email found for registration");
        require(employerEmailToAddress[experience.employerEmail] == address(0), "Email already registered");

        // Update employer details
        experience.employerAddress = employerAddress;
        experience.employerEnsName = employerEnsName;
        experience.employerStatus = EmployerStatus.Registered;
        experience.attestationStatus = AttestationStatus.Pending;

        // Map email to the new employer address
        employerEmailToAddress[experience.employerEmail] = employerAddress;

        // Add experienceId to employer's list
        employerExperienceIds[employerAddress].push(experienceId);

        // Remove experienceId from employerEmailExperiences
        uint32[] storage emailExperiences = employerEmailExperiences[experience.employerEmail];
        for (uint256 i = 0; i < emailExperiences.length; i++) {
            if (emailExperiences[i] == experienceId) {
                emailExperiences[i] = emailExperiences[emailExperiences.length - 1]; // Replace with the last element
                emailExperiences.pop(); // Remove the last element
                break;
            }
        }

        emit EmployerRegistered(experienceId, employerAddress, employerEnsName);
    }

    function signAttestation(uint32 experienceId, address seeker) 
        external 
        validExperienceId(experienceId) 
        nonReentrant returns (uint64)
    {
        Experience storage experience = experiences[experienceId];
        require(experience.seekerAddress == seeker, "Invalid seeker");
        require(msg.sender == experience.employerAddress, "Only assigned employer can sign");
        require(experience.attestationStatus == AttestationStatus.Pending, "Attestation not pending");
        require(experience.employerStatus == EmployerStatus.Registered, "Employer not registered");

        bytes memory data = abi.encode(
            experience.role,
            experience.employerName,
            experience.employerAddress,
            experience.employerEnsName,
            experience.seekerName,
            experience.seekerAddress,
            experience.seekerEnsName,
            experience.startMonth,
            experience.startYear,
            experience.endMonth,
            experience.endYear,
            experience.employmentType
        );

        bytes[] memory recipients = new bytes[](2);
        recipients[0] = abi.encode(seeker);
        recipients[1] = abi.encode(msg.sender);

        Attestation memory a = Attestation({
            schemaId: schemaId,
            linkedAttestationId: 0,
            attestTimestamp: 0,
            revokeTimestamp: 0,
            attester: address(this),
            validUntil: 0,
            dataLocation: DataLocation.ONCHAIN,
            revoked: false,
            recipients: recipients,
            data: data
        });

        uint64 attestationId = spInstance.attest(a, experience.employerEnsName, "", "");
        require(attestationId != 0, "Attestation failed");

        experience.attestationStatus = AttestationStatus.Signed;
        emit AttestationSigned(experienceId, seeker, msg.sender, attestationId);
        
        return attestationId;
    }

    function rejectAttestation(uint32 experienceId) external validExperienceId(experienceId) {
        Experience storage experience = experiences[experienceId];
        require(msg.sender == experience.employerAddress, "Only assigned employer can reject");
        require(experience.attestationStatus == AttestationStatus.Pending, "Attestation not pending");

        experience.attestationStatus = AttestationStatus.Rejected;
        emit AttestationRejected(experienceId);
    }

    // View functions
    function getExperienceById(uint32 experienceId) 
        external 
        view 
        validExperienceId(experienceId) 
        returns (Experience memory) 
    {
        return experiences[experienceId];
    }

    function getUserExperiences(address user) external view returns (Experience[] memory) {
        uint32[] memory ids = userExperienceIds[user];
        Experience[] memory userExperiences = new Experience[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            userExperiences[i] = experiences[ids[i]];
        }
        return userExperiences;
    }

    function getEmployerExperiences(address employer) external view returns (Experience[] memory) {
        uint32[] memory ids = employerExperienceIds[employer];
        Experience[] memory employerExperiences = new Experience[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            employerExperiences[i] = experiences[ids[i]];
        }
        return employerExperiences;
    }

    function getExperiencesByEmail(string memory email) external view returns (Experience[] memory) {
        uint32[] memory ids = employerEmailExperiences[email];
        Experience[] memory experiencesByEmail = new Experience[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            experiencesByEmail[i] = experiences[ids[i]];
        }
        return experiencesByEmail;
    }

    // Fetch array of experience IDs for a user
    function getUserExperienceIds(address user) 
        external 
        view 
        returns (uint32[] memory) 
    {
        return userExperienceIds[user];
    }

    // Fetch array of experience IDs for an employer
    function getEmployerExperienceIds(address employer) 
        external 
        view 
        returns (uint32[] memory) 
    {
        return employerExperienceIds[employer];
    }
}